# frozen_string_literal: true

require 'sorbet-runtime'
require 'dry-configurable'
require 'securerandom'
require_relative 'context'
require_relative 'callbacks'

module DSPy
  class Module
    extend T::Sig
    extend T::Generic
    include Dry::Configurable
    include DSPy::Callbacks

    DEFAULT_MODULE_SUBSCRIPTION_SCOPE = :descendants

    module ForwardOverrideHooks
      def method_added(method_name)
        super

        return unless method_name == :forward
        return if self == DSPy::Module
        return if @_wrapping_forward

        @_wrapping_forward = true

        original = instance_method(:forward)
        define_method(:forward) do |*args, **kwargs, &block|
          instrument_forward_call(args, kwargs) do
            original.bind(self).call(*args, **kwargs, &block)
          end
        end
      ensure
        @_wrapping_forward = false
      end
    end

    class << self
      def inherited(subclass)
        super
        specs_copy = module_subscription_specs.map(&:dup)
        subclass.instance_variable_set(:@module_subscription_specs, specs_copy)
        subclass.extend(ForwardOverrideHooks)
      end

      def subscribe(pattern, handler = nil, scope: DEFAULT_MODULE_SUBSCRIPTION_SCOPE, &block)
        raise ArgumentError, 'Provide a handler method or block' if handler.nil? && block.nil?
        validate_subscription_scope!(scope)

        module_subscription_specs << {
          pattern: pattern,
          handler: handler,
          block: block,
          scope: scope
        }
      end

      def module_subscription_specs
        @module_subscription_specs ||= []
      end

      private

      def validate_subscription_scope!(scope)
        return if [:descendants, :self].include?(scope)

        raise ArgumentError, "Unsupported subscription scope: #{scope.inspect}"
      end
    end

    # Per-instance LM configuration
    setting :lm, default: nil

    # Enable callback hooks for forward method
    create_before_callback :forward
    create_after_callback :forward
    create_around_callback :forward

    # The main forward method that users will call is generic and type parameterized
    sig do
      type_parameters(:I, :O)
        .params(
          input_values: T.type_parameter(:I)
        )
        .returns(T.type_parameter(:O))
    end
    def forward(**input_values)
      instrument_forward_call([], input_values) do
        result = forward_untyped(**input_values)
        T.cast(result, T.type_parameter(:O))
      end
    end

    # The implementation method that subclasses must override
    sig { params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      raise NotImplementedError, "Subclasses must implement forward_untyped method"
    end

    # The main call method that users will call is generic and type parameterized
    sig do
      type_parameters(:I, :O)
        .params(
          input_values: T.type_parameter(:I)
        )
        .returns(T.type_parameter(:O))
    end
    def call(**input_values)
      forward(**input_values)
    end

    # The implementation method for call
    sig { params(input_values: T.untyped).returns(T.untyped) }
    def call_untyped(**input_values)
      forward_untyped(**input_values)
    end

    # Get the configured LM for this instance, checking fiber-local context first
    sig { returns(T.untyped) }
    def lm
      config.lm || DSPy.current_lm
    end

    # Save the module state to a JSON file
    # Lightweight serialization for intermediate optimization trials
    #
    # @param path [String] Path to save the module state (JSON format)
    sig { params(path: String).void }
    def save(path)
      require 'json'
      require 'fileutils'

      # Ensure parent directory exists
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      # Serialize module to JSON
      File.write(path, JSON.pretty_generate(to_h))
    end

    # Default serialization method - subclasses can override
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        class_name: self.class.name,
        state: {}
      }
    end

    # Discover nested predictor modules (Python parity helper)
    sig { returns(T::Array[[String, DSPy::Module]]) }
    def named_predictors
      []
    end

    sig { returns(T::Array[DSPy::Module]) }
    def predictors
      named_predictors.map { |(_, predictor)| predictor }
    end

    def instrument_forward_call(call_args, call_kwargs)
      ensure_module_subscriptions!

      DSPy::Context.with_module(self) do
        observation_type = DSPy::ObservationType.for_module_class(self.class)
        span_attributes = observation_type.langfuse_attributes.merge(
          'langfuse.observation.input' => serialize_module_input(call_args, call_kwargs),
          'dspy.module' => self.class.name
        )

        DSPy::Context.with_span(
          operation: "#{self.class.name}.forward",
          **span_attributes
        ) do |span|
          yield.tap do |result|
            if span && result
              span.set_attribute('langfuse.observation.output', serialize_module_output(result))
            end
          end
        end
      end
    end

    def serialize_module_input(call_args, call_kwargs)
      payload = if call_kwargs && !call_kwargs.empty?
        call_kwargs
      elsif call_args && !call_args.empty?
        call_args
      else
        {}
      end

      payload.to_json
    rescue StandardError
      payload.to_s
    end

    def serialize_module_output(result)
      if result.respond_to?(:to_h)
        result.to_h.to_json
      else
        result.to_json
      end
    rescue StandardError
      result.to_s
    end

    private :instrument_forward_call, :serialize_module_input, :serialize_module_output

    sig { returns(String) }
    def module_scope_id
      @module_scope_id ||= SecureRandom.uuid
    end

    sig { returns(T.nilable(String)) }
    def module_scope_label
      @module_scope_label
    end

    sig { params(label: T.nilable(String)).void }
    def module_scope_label=(label)
      @module_scope_label = label
    end

    sig { returns(T::Array[String]) }
    def registered_module_subscriptions
      Array(@module_subscription_ids).dup
    end

    sig { void }
    def unsubscribe_module_events
      Array(@module_subscription_ids).each { |id| DSPy.events.unsubscribe(id) }
      @module_subscription_ids = []
      @module_subscriptions_registered = false
    end

    private

    def ensure_module_subscriptions!
      return if @module_subscriptions_registered

      specs = self.class.module_subscription_specs
      if specs.empty?
        @module_subscriptions_registered = true
        return
      end

      @module_subscription_ids ||= []
      specs.each do |spec|
        callback = build_subscription_callback(spec)
        subscription_id = DSPy.events.subscribe(spec[:pattern], &callback)
        @module_subscription_ids << subscription_id
      end

      @module_subscriptions_registered = true
    end

    def build_subscription_callback(spec)
      scope = spec[:scope] || DEFAULT_MODULE_SUBSCRIPTION_SCOPE
      handler = spec[:handler]
      block = spec[:block]

      proc do |event_name, attributes|
        next unless module_event_within_scope?(attributes, scope)

        if handler
          send(handler, event_name, attributes)
        else
          instance_exec(event_name, attributes, &block)
        end
      end
    end

    def module_event_within_scope?(attributes, scope)
      metadata = extract_module_metadata(attributes)
      return false unless metadata

      case scope
      when :self
        metadata[:leaf_id] == module_scope_id
      else
        metadata[:path_ids].include?(module_scope_id)
      end
    end

    def extract_module_metadata(attributes)
      path = attributes[:module_path] || attributes['module_path']
      leaf = attributes[:module_leaf] || attributes['module_leaf']
      return nil unless path.is_a?(Array)

      {
        path_ids: path.map { |entry| entry[:id] || entry['id'] }.compact,
        leaf_id: leaf&.dig(:id) || leaf&.dig('id')
      }
    end
  end
end
