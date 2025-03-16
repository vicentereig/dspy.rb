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
        class_eval do
          attr_accessor name.to_sym          
        end
        @input_fields ||= {}
        @input_fields[name] = InputField.new(name, type, desc: desc)
      end
      
      def output(name, type, desc: nil)
        class_eval do
          attr_accessor name.to_sym          
        end
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
  end
end 