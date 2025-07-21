# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'signature'

module DSPy
  # Represents a typed training/evaluation example with Signature validation
  # Provides early validation and type safety for evaluation workflows
  class Example
    extend T::Sig

    sig { returns(T.class_of(Signature)) }
    attr_reader :signature_class

    sig { returns(T::Struct) }
    attr_reader :input

    sig { returns(T::Struct) }
    attr_reader :expected

    sig { returns(T.nilable(String)) }
    attr_reader :id

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    attr_reader :metadata

    sig do
      params(
        signature_class: T.class_of(Signature),
        input: T::Hash[Symbol, T.untyped],
        expected: T::Hash[Symbol, T.untyped],
        id: T.nilable(String),
        metadata: T.nilable(T::Hash[Symbol, T.untyped])
      ).void
    end
    def initialize(signature_class:, input:, expected:, id: nil, metadata: nil)
      @signature_class = signature_class
      @id = id
      @metadata = metadata&.freeze

      # Validate and create input struct
      begin
        @input = signature_class.input_struct_class.new(**input)
      rescue ArgumentError => e
        raise ArgumentError, "Invalid input for #{signature_class.name}: #{e.message}"
      rescue TypeError => e
        raise TypeError, "Type error in input for #{signature_class.name}: #{e.message}"
      end

      # Validate and create expected output struct
      begin
        @expected = signature_class.output_struct_class.new(**expected)
      rescue ArgumentError => e
        raise ArgumentError, "Invalid expected output for #{signature_class.name}: #{e.message}"
      rescue TypeError => e
        raise TypeError, "Type error in expected output for #{signature_class.name}: #{e.message}"
      end
    end

    # Convert input struct to hash for program execution
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def input_values
      input_hash = {}
      @input.class.props.keys.each do |key|
        input_hash[key] = @input.send(key)
      end
      input_hash
    end

    # Convert expected struct to hash for comparison
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def expected_values
      expected_hash = {}
      @expected.class.props.keys.each do |key|
        expected_hash[key] = @expected.send(key)
      end
      expected_hash
    end

    # Custom equality comparison
    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      return false unless other.is_a?(Example)
      
      @signature_class == other.signature_class &&
        input_values == other.input_values &&
        expected_values == other.expected_values
    end


    # Check if prediction matches expected output using struct comparison
    sig { params(prediction: T.untyped).returns(T::Boolean) }
    def matches_prediction?(prediction)
      return false unless prediction

      # Compare each expected field with prediction
      @expected.class.props.keys.all? do |key|
        expected_value = @expected.send(key)
        
        # Extract prediction value
        prediction_value = case prediction
                          when T::Struct
                            prediction.respond_to?(key) ? prediction.send(key) : nil
                          when Hash
                            prediction[key] || prediction[key.to_s]
                          else
                            prediction.respond_to?(key) ? prediction.send(key) : nil
                          end
        
        expected_value == prediction_value
      end
    end

    # Serialization for persistence and debugging
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      result = {
        signature_class: @signature_class.name,
        input: input_values,
        expected: expected_values
      }
      
      result[:id] = @id if @id
      result[:metadata] = @metadata if @metadata
      result
    end

    # Create Example from hash representation
    sig do
      params(
        hash: T::Hash[Symbol, T.untyped],
        signature_registry: T.nilable(T::Hash[String, T.class_of(Signature)])
      ).returns(Example)
    end
    def self.from_h(hash, signature_registry: nil)
      signature_class_name = hash[:signature_class]
      
      # Resolve signature class
      signature_class = if signature_registry && signature_registry[signature_class_name]
                         signature_registry[signature_class_name]
                       else
                         # Try to resolve from constant
                         Object.const_get(signature_class_name)
                       end
      
      new(
        signature_class: signature_class,
        input: hash[:input] || {},
        expected: hash[:expected] || {},
        id: hash[:id],
        metadata: hash[:metadata]
      )
    end


    # Batch validation for multiple examples
    sig do
      params(
        signature_class: T.class_of(Signature),
        examples_data: T::Array[T::Hash[Symbol, T.untyped]]
      ).returns(T::Array[Example])
    end
    def self.validate_batch(signature_class, examples_data)
      errors = []
      examples = []
      
      examples_data.each_with_index do |example_data, index|
        begin
          # Only support structured format with :input and :expected keys
          unless example_data.key?(:input) && example_data.key?(:expected)
            raise ArgumentError, "Example must have :input and :expected keys. Legacy flat format is no longer supported."
          end
          
          example = new(
            signature_class: signature_class,
            input: example_data[:input],
            expected: example_data[:expected],
            id: example_data[:id] || "example_#{index}"
          )
          examples << example
        rescue => e
          errors << "Example #{index}: #{e.message}"
        end
      end
      
      unless errors.empty?
        raise ArgumentError, "Validation errors:\n#{errors.join("\n")}"
      end
      
      examples
    end


    # String representation for debugging
    sig { returns(String) }
    def to_s
      "DSPy::Example(#{@signature_class.name}) input=#{format_hash(input_values)} expected=#{format_hash(expected_values)}"
    end
    
    private
    
    # Format hash without escaping Unicode characters
    sig { params(hash: T::Hash[Symbol, T.untyped]).returns(String) }
    def format_hash(hash)
      pairs = hash.map do |k, v|
        value_str = case v
                    when String
                      # Don't escape Unicode characters
                      "\"#{v}\""
                    else
                      v.inspect
                    end
        ":#{k} => #{value_str}"
      end
      "{#{pairs.join(", ")}}"
    end
    
    public

    sig { returns(String) }
    def inspect
      to_s
    end
  end
end