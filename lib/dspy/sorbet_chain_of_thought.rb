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
    
    sig { params(signature_class: T.class_of(DSPy::SorbetSignature)).void }
    def initialize(signature_class)
      @original_signature = signature_class
      
      # Create enhanced output struct with reasoning
      enhanced_output_struct = create_enhanced_output_struct(signature_class)
      
      # Create enhanced signature class
      enhanced_signature = Class.new(DSPy::SorbetSignature) do
        # Set the description
        description "#{signature_class.description} Think step by step."
        
        # Use the same input struct
        @input_struct_class = signature_class.input_struct_class
        
        # Use the enhanced output struct
        @output_struct_class = enhanced_output_struct
        
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
