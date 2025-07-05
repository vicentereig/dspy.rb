# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'few_shot_example'

module DSPy
  class Prompt
    extend T::Sig

    sig { returns(String) }
    attr_reader :instruction

    sig { returns(T::Array[FewShotExample]) }
    attr_reader :few_shot_examples

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :input_schema

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :output_schema

    sig { returns(T.nilable(String)) }
    attr_reader :signature_class_name

    sig do
      params(
        instruction: String,
        input_schema: T::Hash[Symbol, T.untyped],
        output_schema: T::Hash[Symbol, T.untyped],
        few_shot_examples: T::Array[FewShotExample],
        signature_class_name: T.nilable(String)
      ).void
    end
    def initialize(instruction:, input_schema:, output_schema:, few_shot_examples: [], signature_class_name: nil)
      @instruction = instruction
      @few_shot_examples = few_shot_examples.freeze
      @input_schema = input_schema.freeze
      @output_schema = output_schema.freeze
      @signature_class_name = signature_class_name
    end

    # Immutable update methods for optimization
    sig { params(new_instruction: String).returns(Prompt) }
    def with_instruction(new_instruction)
      self.class.new(
        instruction: new_instruction,
        input_schema: @input_schema,
        output_schema: @output_schema,
        few_shot_examples: @few_shot_examples,
        signature_class_name: @signature_class_name
      )
    end

    sig { params(new_examples: T::Array[FewShotExample]).returns(Prompt) }
    def with_examples(new_examples)
      self.class.new(
        instruction: @instruction,
        input_schema: @input_schema,
        output_schema: @output_schema,
        few_shot_examples: new_examples,
        signature_class_name: @signature_class_name
      )
    end

    sig { params(new_examples: T::Array[FewShotExample]).returns(Prompt) }
    def add_examples(new_examples)
      combined_examples = @few_shot_examples + new_examples
      with_examples(combined_examples)
    end

    # Core prompt rendering methods
    sig { returns(String) }
    def render_system_prompt
      sections = []
      
      sections << "Your input schema fields are:"
      sections << "```json"
      sections << JSON.pretty_generate(@input_schema)
      sections << "```"
      
      sections << "Your output schema fields are:"
      sections << "```json"
      sections << JSON.pretty_generate(@output_schema)
      sections << "```"
      
      sections << ""
      sections << "All interactions will be structured in the following way, with the appropriate values filled in."
      
      # Add few-shot examples if present
      if @few_shot_examples.any?
        sections << ""
        sections << "Here are some examples:"
        sections << ""
        @few_shot_examples.each_with_index do |example, index|
          sections << "### Example #{index + 1}"
          sections << example.to_prompt_section
          sections << ""
        end
      end

      sections << "## Input values"
      sections << "```json"
      sections << "{input_values}"
      sections << "```"
      
      sections << "## Output values"
      sections << "Respond exclusively with the output schema fields in the json block below."
      sections << "```json"
      sections << "{output_values}"
      sections << "```"
      
      sections << ""
      sections << "In adhering to this structure, your objective is: #{@instruction}"
      
      sections.join("\n")
    end

    sig { params(input_values: T::Hash[Symbol, T.untyped]).returns(String) }
    def render_user_prompt(input_values)
      sections = []
      
      sections << "## Input Values"
      sections << "```json"
      sections << JSON.pretty_generate(serialize_for_json(input_values))
      sections << "```"
      
      sections << ""
      sections << "Respond with the corresponding output schema fields wrapped in a ```json ``` block,"
      sections << "starting with the heading `## Output values`."
      
      sections.join("\n")
    end

    # Generate messages for LM adapter
    sig { params(input_values: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, String]]) }
    def to_messages(input_values)
      [
        { role: 'system', content: render_system_prompt },
        { role: 'user', content: render_user_prompt(input_values) }
      ]
    end

    # Serialization for persistence and optimization
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        instruction: @instruction,
        few_shot_examples: @few_shot_examples.map(&:to_h),
        input_schema: @input_schema,
        output_schema: @output_schema,
        signature_class_name: @signature_class_name
      }
    end

    sig { params(hash: T::Hash[Symbol, T.untyped]).returns(Prompt) }
    def self.from_h(hash)
      examples = (hash[:few_shot_examples] || []).map { |ex| FewShotExample.from_h(ex) }
      
      new(
        instruction: hash[:instruction] || "",
        input_schema: hash[:input_schema] || {},
        output_schema: hash[:output_schema] || {},
        few_shot_examples: examples,
        signature_class_name: hash[:signature_class_name]
      )
    end

    # Create prompt from signature class
    sig { params(signature_class: T.class_of(Signature)).returns(Prompt) }
    def self.from_signature(signature_class)
      new(
        instruction: signature_class.description || "Complete this task.",
        input_schema: signature_class.input_json_schema,
        output_schema: signature_class.output_json_schema,
        few_shot_examples: [],
        signature_class_name: signature_class.name
      )
    end

    # Comparison and diff methods for optimization
    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      return false unless other.is_a?(Prompt)
      
      @instruction == other.instruction &&
        @few_shot_examples == other.few_shot_examples &&
        @input_schema == other.input_schema &&
        @output_schema == other.output_schema
    end

    sig { params(other: Prompt).returns(T::Hash[Symbol, T.untyped]) }
    def diff(other)
      changes = {}
      
      changes[:instruction] = {
        from: @instruction,
        to: other.instruction
      } if @instruction != other.instruction
      
      changes[:few_shot_examples] = {
        from: @few_shot_examples.length,
        to: other.few_shot_examples.length,
        added: other.few_shot_examples - @few_shot_examples,
        removed: @few_shot_examples - other.few_shot_examples
      } if @few_shot_examples != other.few_shot_examples
      
      changes
    end

    # Statistics for optimization tracking
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def stats
      {
        character_count: @instruction.length,
        example_count: @few_shot_examples.length,
        total_example_chars: @few_shot_examples.sum { |ex| ex.to_prompt_section.length },
        input_fields: @input_schema.dig(:properties)&.keys&.length || 0,
        output_fields: @output_schema.dig(:properties)&.keys&.length || 0
      }
    end

    private

    # Recursively serialize complex objects for JSON representation
    sig { params(obj: T.untyped).returns(T.untyped) }
    def serialize_for_json(obj)
      case obj
      when T::Struct
        # Convert T::Struct to hash using to_h method if available
        if obj.respond_to?(:to_h)
          serialize_for_json(obj.to_h)
        else
          # Fallback: serialize using struct properties
          serialize_struct_to_hash(obj)
        end
      when Hash
        # Recursively serialize hash values
        obj.transform_values { |v| serialize_for_json(v) }
      when Array
        # Recursively serialize array elements
        obj.map { |item| serialize_for_json(item) }
      when T::Enum
        # Serialize enums to their string representation
        obj.serialize
      else
        # For basic types (String, Integer, Float, Boolean, etc.), return as-is
        obj
      end
    end

    # Fallback method to serialize T::Struct to hash when to_h is not available
    sig { params(struct_obj: T::Struct).returns(T::Hash[Symbol, T.untyped]) }
    def serialize_struct_to_hash(struct_obj)
      result = {}
      
      # Use struct's props method to get all properties
      if struct_obj.class.respond_to?(:props)
        struct_obj.class.props.each do |prop_name, _prop_info|
          if struct_obj.respond_to?(prop_name)
            value = struct_obj.public_send(prop_name)
            result[prop_name] = serialize_for_json(value)
          end
        end
      end
      
      result
    end
  end
end