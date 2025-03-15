# frozen_string_literal: true

module DSPy
  class Signature
    class << self
      attr_reader :instructions, :input_fields, :output_fields

      def description(text = nil)
        if text
          @description = text
        else
          @description
        end
      end
      
      def input(name, type, desc: nil)
        @input_fields ||= {}
        @input_fields[name] = InputField.new(name, type, desc: desc)
      end
      
      def output(name, type, desc: nil)
        @output_fields ||= {}
        @output_fields[name] = OutputField.new(name, type, desc: desc)
      end
      
      def new_from_hash(hash)
        instance = new
        hash.each do |key, value|
          instance.instance_variable_set(:"@#{key}", value)
        end
        instance
      end
    end
    
    # Allow getting field values via methods
    def method_missing(name, *args, &block)
      if instance_variable_defined?(:"@#{name}")
        instance_variable_get(:"@#{name}")
      else
        super
      end
    end
    
    def respond_to_missing?(name, include_private = false)
      instance_variable_defined?(:"@#{name}") || super
    end
  end
end 