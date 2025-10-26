# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'

module DSPy
  # Provides Rails-style callback hooks for DSPy modules
  #
  # @example Define callbacks in base class
  #   class DSPy::Module
  #     include DSPy::Callbacks
  #
  #     create_before_callback :forward
  #     create_after_callback :forward
  #     create_around_callback :forward
  #   end
  #
  # @example Use callbacks in subclasses
  #   class MyAgent < DSPy::Module
  #     before :setup_context
  #     after :log_metrics
  #     around :manage_memory
  #
  #     private
  #
  #     def setup_context
  #       @start_time = Time.now
  #     end
  #
  #     def log_metrics
  #       puts "Duration: #{Time.now - @start_time}"
  #     end
  #
  #     def manage_memory
  #       load_context
  #       yield
  #       save_context
  #     end
  #   end
  module Callbacks
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Configures a method to expose before callbacks.
      #
      # @param method_name [Symbol] the target method.
      # @param wrap [Boolean] When true (default), the method is transparently wrapped so callbacks
      #   run automatically on every invocation. Pass false when you plan to trigger callbacks
      #   manually (e.g., to interleave custom spans or thread management). Manual targets are
      #   never re-wrapped, so execution order stays entirely in your control.
      # Creates a before callback hook for the specified method
      #
      # @param method_name [Symbol] the method to add callback support to
      def create_before_callback(method_name, wrap: true)
        mark_method_has_callbacks(method_name, wrap: wrap)
        ensure_callback_method_defined(:before, method_name)
        wrap_method_with_callbacks(method_name) if wrap
      end

      # Creates an after callback hook for the specified method
      #
      # @param method_name [Symbol] the method to add callback support to
      def create_after_callback(method_name, wrap: true)
        mark_method_has_callbacks(method_name, wrap: wrap)
        ensure_callback_method_defined(:after, method_name)
        wrap_method_with_callbacks(method_name) if wrap
      end

      # Creates an around callback hook for the specified method
      #
      # @param method_name [Symbol] the method to add callback support to
      def create_around_callback(method_name, wrap: true)
        mark_method_has_callbacks(method_name, wrap: wrap)
        ensure_callback_method_defined(:around, method_name)
        wrap_method_with_callbacks(method_name) if wrap
      end

      private

      # Ensures the callback registration method exists
      def ensure_callback_method_defined(type, target_method_name)
        set_default_callback_target(type, target_method_name)

        return if singleton_class.method_defined?(type)

        define_singleton_method(type) do |callback_method = nil, target: default_callback_target(type), &block|
          callback = callback_method || block
          raise ArgumentError, "No callback provided for #{type}" unless callback

          register_callback(type, target || default_callback_target(type), callback)
        end
      end

      # Registers a callback for execution
      def register_callback(type, method_name, callback)
        own_callbacks_for(method_name)[type] ||= []
        own_callbacks_for(method_name)[type] << callback
      end

      # Returns own callbacks (not including parent)
      def own_callbacks_for(method_name)
        @callbacks ||= {}
        @callbacks[method_name] ||= {}
      end

      # Marks that a method has callback support (even if no callbacks registered yet)
      def mark_method_has_callbacks(method_name, wrap: true)
        own_callbacks_for(method_name)
        manual_callback_targets << method_name unless wrap
      end

      # Returns the callback registry for a method
      # Includes callbacks from parent classes
      def callbacks_for(method_name)
        own_callbacks = own_callbacks_for(method_name)

        # Merge parent callbacks if this is a subclass
        if superclass.respond_to?(:callbacks_for, true)
          parent_callbacks = superclass.send(:callbacks_for, method_name)

          # Merge each callback type, with own callbacks coming after parent callbacks
          merged_callbacks = {}
          [:before, :after, :around].each do |type|
            parent_list = parent_callbacks[type] || []
            own_list = own_callbacks[type] || []
            merged_callbacks[type] = parent_list + own_list if parent_list.any? || own_list.any?
          end

          merged_callbacks
        else
          own_callbacks
        end
      end

      # Wraps a method with callback execution logic
      def wrap_method_with_callbacks(method_name)
        return if method_wrapped?(method_name)

        # Defer wrapping if method doesn't exist yet
        return unless method_defined?(method_name)

        # Mark as wrapped BEFORE define_method to prevent infinite recursion
        mark_method_wrapped(method_name)

        original_method = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs, &block|
          # Execute before callbacks
          run_callbacks(:before, method_name)

          # Execute around callbacks or original method
          result = if self.class.send(:has_around_callbacks?, method_name)
            execute_with_around_callbacks(method_name, original_method, *args, **kwargs, &block)
          else
            original_method.bind(self).call(*args, **kwargs, &block)
          end

          # Execute after callbacks
          run_callbacks(:after, method_name)

          result
        end
      end

      # Checks if method has around callbacks
      def has_around_callbacks?(method_name)
        callbacks_for(method_name)[:around]&.any?
      end

      # Hook into method_added to wrap methods when they're defined
      def method_added(method_name)
        super

        # Check if this method or any parent has callback support (even if no callbacks registered yet)
        has_callback_support = method_has_callback_support?(method_name)

        return unless has_callback_support
        return if method_wrapped?(method_name)
        return if manual_callback_targets.include?(method_name)

        wrap_method_with_callbacks(method_name)
      end

      # Checks if a method has callback support in this class or parents
      def method_has_callback_support?(method_name)
        # Check own callbacks registry
        return true if @callbacks&.key?(method_name)

        # Check parent class
        if superclass.respond_to?(:method_has_callback_support?, true)
          superclass.send(:method_has_callback_support?, method_name)
        else
          false
        end
      end

      # Marks a method as wrapped
      def mark_method_wrapped(method_name)
        @wrapped_methods ||= []
        @wrapped_methods << method_name
      end

      # Checks if method is already wrapped
      def method_wrapped?(method_name)
        @wrapped_methods&.include?(method_name)
      end

      def manual_callback_targets
        @manual_callback_targets ||= Set.new
      end

      def callback_defaults
        @callback_defaults ||= {}
      end

      def set_default_callback_target(type, method_name)
        callback_defaults[type] ||= method_name
      end

      def default_callback_target(type)
        callback_defaults[type] || begin
          if superclass.respond_to?(:default_callback_target, true)
            superclass.send(:default_callback_target, type)
          end
        end
      end
    end

    private

    # Executes callbacks of a specific type
    def run_callbacks(type, method_name, payload = nil)
      callbacks = self.class.send(:callbacks_for, method_name)[type]
      return unless callbacks

      callbacks.each do |callback|
        case callback
        when Symbol
          method_obj = method(callback)
          if method_obj.arity.zero?
            send(callback)
          else
            send(callback, payload)
          end
        when Proc
          if callback.arity.zero?
            instance_exec(&callback)
          else
            instance_exec(payload, &callback)
          end
        else
          callback.call(payload)
        end
      end
    end

    # Executes method with around callbacks
    def execute_with_around_callbacks(method_name, original_method, *args, **kwargs, &block)
      callbacks = self.class.send(:callbacks_for, method_name)[:around]
      args_copy = args.dup
      kwargs_copy = kwargs.dup

      # Build callback chain from innermost (original method) to outermost
      chain = callbacks.reverse.inject(
        -> { original_method.bind(self).call(*args, **kwargs, &block) }
      ) do |inner, callback|
        if callback.is_a?(Proc)
          -> do
            next_proc = -> { inner.call }
            proc_arity = callback.arity
            expects_extra = proc_arity.abs > 1

            if expects_extra
              instance_exec(next_proc, args_copy, kwargs_copy, &callback)
            else
              instance_exec(next_proc, &callback)
            end
          end
        else
          -> do
            method_obj = method(callback)
            if method_obj.arity.zero?
              send(callback) { inner.call }
            else
              send(callback, args_copy, kwargs_copy) { inner.call }
            end
          end
        end
      end

      chain.call
    end
  end
end
