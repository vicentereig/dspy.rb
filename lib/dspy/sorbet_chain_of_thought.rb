# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'sorbet_predict'
require_relative 'sorbet_signature'

module DSPy
  # Enhances prediction by encouraging step-by-step reasoning
  # before providing a final answer using Sorbet signatures.
  class SorbetChainOfThought < SorbetPredict
    extend T::Sig
    
    FieldDescriptor = DSPy::SorbetSignature::FieldDescriptor
    
    sig { params(signature_class: T.class_of(DSPy::SorbetSignature)).void }
    def initialize(signature_class)
      @original_signature = signature_class
      
      # Create enhanced output struct with reasoning
      enhanced_output_struct = create_enhanced_output_struct(signature_class)
      
      # Create enhanced signature class
      enhanced_signature = Class.new(DSPy::SorbetSignature) do
        # Set the description
        description "#{signature_class.description} Think step by step."
        
        # Use the same input struct and copy field descriptors
        @input_struct_class = signature_class.input_struct_class
        @input_field_descriptors = signature_class.instance_variable_get(:@input_field_descriptors) || {}
        
        # Use the enhanced output struct and create field descriptors for it
        @output_struct_class = enhanced_output_struct
        
        # Create field descriptors for the enhanced output struct
        @output_field_descriptors = {}
        
        # Copy original output field descriptors
        original_output_descriptors = signature_class.instance_variable_get(:@output_field_descriptors) || {}
        @output_field_descriptors.merge!(original_output_descriptors)
        
        # Add reasoning field descriptor
        @output_field_descriptors[:reasoning] = FieldDescriptor.new(String, nil)
        
        class << self
          attr_reader :input_struct_class, :output_struct_class
        end
      end
      
      # Call parent constructor with enhanced signature
      super(enhanced_signature)
    end
    
    private
    
    sig { params(signature_class: T.class_of(DSPy::SorbetSignature)).returns(T.class_of(T::Struct)) }
    def create_enhanced_output_struct(signature_class)
      # Get original output props
      original_props = signature_class.output_struct_class.props
      
      # Create new struct class with reasoning added
      Class.new(T::Struct) do
        # Add all original fields
        original_props.each do |name, prop|
          # Extract the type and other options
          type = prop[:type]
          options = prop.except(:type, :type_object, :accessor_key, :sensitivity, :redaction)
          
          # Handle default values
          if options[:default]
            const name, type, default: options[:default]
          elsif options[:factory]
            const name, type, factory: options[:factory]
          else
            const name, type
          end
        end
        
        # Add reasoning field
        const :reasoning, String
        
        # Add to_h method to serialize the struct to a hash
        define_method :to_h do
          hash = {}
          
          # Start with input values if available
          if self.instance_variable_defined?(:@input_values)
            hash.merge!(self.instance_variable_get(:@input_values))
          end
          
          # Then add output properties
          self.class.props.keys.each do |key|
            hash[key] = self.send(key)
          end
          
          hash
        end
      end
    end
    
    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def generate_example_output
      example = super
      example[:reasoning] = "Let me think through this step by step..."
      example
    end
  end
end
