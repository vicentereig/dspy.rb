# frozen_string_literal: true

require 'sorbet-runtime'
require 'dry-configurable'
require 'securerandom'
require 'weakref'
require_relative 'context'
require_relative 'callbacks'
require_relative 'type_serializer'
require 'json'

module DSPy
  class Module
    extend T::Sig
    extend T::Generic
    include Dry::Configurable
    include DSPy::Callbacks

    class SubcriptionScope < T::Enum
      enums do
        Descendants = new('descendants')
        SelfOnly    = new('self')
      end
    end

    DEFAULT_MODULE_SUBSCRIPTION_SCOPE = SubcriptionScope::Descendants

    # Hook to wrap forward methods with instrumentation.
    # Uses a Set-based guard (not boolean) to prevent re-wrapping when
    # other hooks (like Callbacks) also use define_method.
    module ForwardOverrideHooks
      def method_added(method_name)
        super

        return unless method_name == :forward
        return if self == DSPy::Module

        # Use Set-based guard - persists across hook invocations
        @_forward_instrumented ||= Set.new
        return if @_forward_instrumented.include?(object_id)
        @_forward_instrumented << object_id

        original = instance_method(:forward)
        define_method(:forward) do |*args, **kwargs, &block|
          instrument_forward_call(args, kwargs) do
            original.bind(self).call(*args, **kwargs, &block)
          end
        end
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
        scope = normalize_scope(scope)
        raise ArgumentError, 'Provide a handler method or block' if handler.nil? && block.nil?

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

      def build_subscription_callback(weakref, subscription_id_ref, spec)
        scope = spec[:scope] || DEFAULT_MODULE_SUBSCRIPTION_SCOPE
        handler = spec[:handler]
        block = spec[:block]

        ->(event_name, attributes) do
          target = begin
            weakref.__getobj__
          rescue WeakRef::RefError
            nil
          end

          unless target
            subscription_id = subscription_id_ref[:id]
            DSPy.events.unsubscribe(subscription_id) if subscription_id
            DSPy.logger&.debug(event: 'module.subscription.auto_unsubscribe', subscription_id: subscription_id)
            return
          end

          return unless target.send(:module_event_within_scope?, attributes, scope)

          if handler
            target.send(handler, event_name, attributes)
          else
            target.instance_exec(event_name, attributes, &block)
          end
        end
      end

      def validate_subscription_scope!(scope)
        T.must(scope)
      end

      def normalize_scope(scope)
        return scope if scope.is_a?(SubcriptionScope)

        case scope
        when :descendants
          SubcriptionScope::Descendants
        when :self
          SubcriptionScope::SelfOnly
        else
          raise ArgumentError, "Unsupported subscription scope: #{scope.inspect}"
        end
      end
    end

    # Per-instance LM configuration
    setting :lm, default: nil

    # Enable callback hooks for forward method
    create_before_callback :forward
    create_after_callback :forward
    create_around_callback :forward

    # The main forward method that users will call is generic and type parameterized.
    # Instrument here only when subclasses don't override forward.
    sig do
      type_parameters(:I, :O)
        .params(
          input_values: T.type_parameter(:I)
        )
        .returns(T.type_parameter(:O))
    end
    def forward(**input_values)
      result = if self.class.instance_method(:forward).owner == DSPy::Module
        instrument_forward_call([], input_values) do
          forward_untyped(**input_values)
        end
      else
        forward_untyped(**input_values)
      end
      T.cast(result, T.type_parameter(:O))
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

    # Override Dry::Configurable's configure to propagate LM to child predictors
    # When you configure an agent's LM, it automatically propagates to all child predictors
    # returned by named_predictors, recursively.
    #
    # @example Basic usage
    #   agent.configure { |c| c.lm = DSPy::LM.new('openai/gpt-4o') }
    #   # All internal predictors now use gpt-4o
    #
    # @example Fine-grained control (configure then override)
    #   agent.configure { |c| c.lm = cheap_lm }
    #   agent.configure_predictor('thought_generator') { |c| c.lm = expensive_lm }
    #
    # @return [self] for method chaining
    sig { params(block: T.proc.params(config: T.untyped).void).returns(T.self_type) }
    def configure(&block)
      super(&block)
      propagate_lm_to_children(config.lm) if config.lm
      self
    end

    # Configure a specific child predictor by name
    # Use this for fine-grained control when different predictors need different LMs
    #
    # @param predictor_name [String] The name of the predictor (e.g., 'thought_generator')
    # @yield [config] Configuration block
    # @return [self] for method chaining
    # @raise [ArgumentError] if predictor_name is not found
    #
    # @example
    #   agent.configure_predictor('thought_generator') { |c| c.lm = expensive_lm }
    sig { params(predictor_name: String, block: T.proc.params(config: T.untyped).void).returns(T.self_type) }
    def configure_predictor(predictor_name, &block)
      _, predictor = named_predictors.find { |name, _| name == predictor_name }
      unless predictor
        available = named_predictors.map(&:first).join(', ')
        raise ArgumentError, "Unknown predictor: #{predictor_name}. Available: #{available}"
      end
      predictor.configure(&block)
      self
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

      serialized = DSPy::TypeSerializer.serialize(payload)
      JSON.generate(serialized)
    rescue StandardError
      payload.to_s
    end

    def serialize_module_output(result)
      serialized = DSPy::TypeSerializer.serialize(result)
      JSON.generate(serialized)
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

    sig { returns(T.self_type) }
    def dup_for_thread
      cloned = dup
      cloned.instance_variable_set(:@module_subscription_ids, [])
      cloned.instance_variable_set(:@module_subscriptions_registered, false)
      cloned.instance_variable_set(:@module_scope_id, SecureRandom.uuid)
      cloned.send(:reset_thread_state)
      cloned
    end

    private

    def reset_thread_state
      instance_variables.each do |ivar|
        value = instance_variable_get(ivar)
        case value
        when Array, Hash, Set
          instance_variable_set(ivar, value.dup)
        end
      end
    end

    # Propagate LM configuration to child predictors recursively
    # Skips children that already have an explicit LM configured
    sig { params(lm: T.untyped).void }
    def propagate_lm_to_children(lm)
      named_predictors.each do |(name, predictor)|
        next if predictor == self # Skip self-references (Predict returns [['self', self]])

        # Only propagate if child doesn't have explicit LM configured
        unless predictor.config.lm
          # Recursive: configure calls propagate_lm_to_children on the child too
          predictor.configure { |c| c.lm = lm }
        end
      end
    end

    def ensure_module_subscriptions!
      return if @module_subscriptions_registered

      specs = self.class.module_subscription_specs
      if specs.empty?
        @module_subscriptions_registered = true
        return
      end

      @module_subscription_ids ||= []
      specs.each do |spec|
        weakref = WeakRef.new(self)
        subscription_id_ref = { id: nil }
        callback = self.class.send(:build_subscription_callback, weakref, subscription_id_ref, spec)
        subscription_id = DSPy.events.subscribe(spec[:pattern], &callback)
        subscription_id_ref[:id] = subscription_id
        @module_subscription_ids << subscription_id
      end

      @module_subscriptions_registered = true
    end

    def module_event_within_scope?(attributes, scope)
      metadata = extract_module_metadata(attributes)
      return false unless metadata

      case scope
      when SubcriptionScope::SelfOnly
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
