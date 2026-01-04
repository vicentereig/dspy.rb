# frozen_string_literal: true

require 'json'
require 'sorbet-runtime'
require 'sorbet/toon'

require_relative 'few_shot_example'
require_relative 'schema/sorbet_toon_adapter'

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

    sig { returns(Symbol) }
    def schema_format
      @schema_format || :json
    end

    sig { returns(Symbol) }
    def data_format
      @data_format || :json
    end

    sig { returns(T.nilable(T.class_of(Signature))) }
    attr_reader :signature_class

    sig do
      params(
        instruction: String,
        input_schema: T::Hash[Symbol, T.untyped],
        output_schema: T::Hash[Symbol, T.untyped],
        few_shot_examples: T::Array[FewShotExample],
        signature_class_name: T.nilable(String),
        schema_format: T.nilable(Symbol),
        signature_class: T.nilable(T.class_of(Signature)),
        data_format: T.nilable(Symbol)
      ).void
    end
    def initialize(instruction:, input_schema:, output_schema:, few_shot_examples: [], signature_class_name: nil, schema_format: nil, signature_class: nil, data_format: nil)
      @instruction = instruction
      @few_shot_examples = few_shot_examples.freeze
      @input_schema = input_schema.freeze
      @output_schema = output_schema.freeze
      @signature_class_name = signature_class_name
      @schema_format = resolve_schema_format(schema_format)
      @signature_class = signature_class
      @data_format = resolve_data_format(data_format)
    end

    # Immutable update methods for optimization
    sig { params(new_instruction: String).returns(Prompt) }
    def with_instruction(new_instruction)
      self.class.new(
        instruction: new_instruction,
        input_schema: @input_schema,
        output_schema: @output_schema,
        few_shot_examples: @few_shot_examples,
        signature_class_name: @signature_class_name,
        schema_format: @schema_format,
        signature_class: @signature_class,
        data_format: @data_format
      )
    end

    sig { params(new_examples: T::Array[FewShotExample]).returns(Prompt) }
    def with_examples(new_examples)
      self.class.new(
        instruction: @instruction,
        input_schema: @input_schema,
        output_schema: @output_schema,
        few_shot_examples: new_examples,
        signature_class_name: @signature_class_name,
        schema_format: @schema_format,
        signature_class: @signature_class,
        data_format: @data_format
      )
    end

    sig { params(new_examples: T::Array[FewShotExample]).returns(Prompt) }
    def add_examples(new_examples)
      combined_examples = @few_shot_examples + new_examples
      with_examples(combined_examples)
    end

    sig { params(new_schema_format: Symbol).returns(Prompt) }
    def with_schema_format(new_schema_format)
      self.class.new(
        instruction: @instruction,
        input_schema: @input_schema,
        output_schema: @output_schema,
        few_shot_examples: @few_shot_examples,
        signature_class_name: @signature_class_name,
        schema_format: new_schema_format,
        signature_class: @signature_class,
        data_format: @data_format
      )
    end

    sig { params(new_data_format: Symbol).returns(Prompt) }
    def with_data_format(new_data_format)
      self.class.new(
        instruction: @instruction,
        input_schema: @input_schema,
        output_schema: @output_schema,
        few_shot_examples: @few_shot_examples,
        signature_class_name: @signature_class_name,
        schema_format: @schema_format,
        signature_class: @signature_class,
        data_format: new_data_format
      )
    end

    # Core prompt rendering methods
    sig { returns(String) }
    def render_system_prompt
      sections = []

      case schema_format
      when :baml
        sections << "Your input schema fields are:"
        sections << "```baml"
        sections << render_baml_schema(@input_schema, :input)
        sections << "```"

        sections << "Your output schema fields are:"
        sections << "```baml"
        sections << render_baml_schema(@output_schema, :output)
        sections << "```"
      when :toon
        sections << "Your input schema fields (TOON order) are:"
        sections << Sorbet::Toon::SignatureFormatter.describe_signature(@signature_class, :input)
        sections << ""
        sections << "Your output schema fields (TOON order) are:"
        sections << Sorbet::Toon::SignatureFormatter.describe_signature(@signature_class, :output)
      else
        sections << "Your input schema fields are:"
        sections << "```json"
        sections << JSON.pretty_generate(@input_schema)
        sections << "```"

        sections << "Your output schema fields are:"
        sections << "```json"
        sections << JSON.pretty_generate(@output_schema)
        sections << "```"
      end

      sections << ""
      sections << "All interactions will be structured in the following way, with the appropriate values filled in."

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

      if toon_data_format_enabled?
        sections << "## TOON data format instructions"
        sections << "All input and output payloads must use Token-Oriented Object Notation (TOON). Do not return JSON, YAML, or prose."
        sections << ""
        sections << "## Input values"
        sections << "Copy the TOON block below and replace the placeholder values with the correct inputs."
        sections << "```toon"
        sections << "{input_values}"
        sections << "```"

        if (example_input = example_toon_payload(:input))
          sections << ""
          sections << "### Example TOON input"
          sections << "```toon"
          sections << example_input
          sections << "```"
        end

        sections << ""
        sections << "## Output values"
        sections << "Respond exclusively with a ```toon``` block that lists the output fields in the exact order shown in the schema."
        sections << "```toon"
        sections << "{output_values}"
        sections << "```"

        if (example_output = example_toon_payload(:output))
          sections << ""
          sections << "### Example TOON output"
          sections << "```toon"
          sections << example_output
          sections << "```"
        end
      else
        sections << "## Input values"
        sections << "```json"
        sections << "{input_values}"
        sections << "```"

        sections << "## Output values"
        sections << "Respond exclusively with the output schema fields in the json block below."
        sections << "```json"
        sections << "{output_values}"
        sections << "```"
      end

      sections << ""
      sections << "In adhering to this structure, your objective is: #{@instruction}"

      sections.join("\n")
    end

    sig { params(input_values: T::Hash[Symbol, T.untyped]).returns(String) }
    def render_user_prompt(input_values)
      sections = []

      if toon_data_format_enabled?
        toon_payload = DSPy::Schema::SorbetToonAdapter.render_input(@signature_class, input_values)

        sections << "## Input Values"
        sections << "Use the TOON block below as-is; do not convert it to JSON."
        sections << "```toon"
        sections << toon_payload
        sections << "```"
        sections << ""
        sections << "Respond with the corresponding output schema fields encoded as TOON inside a ```toon``` block starting with the heading `## Output values`. Do not include any JSON."
      else
        sections << "## Input Values"
        sections << "```json"
        sections << JSON.pretty_generate(serialize_for_json(input_values))
        sections << "```"
        sections << ""
        sections << "Respond with the corresponding output schema fields wrapped in a ```json ``` block,"
        sections << "starting with the heading `## Output values`."
      end

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
        signature_class_name: @signature_class_name,
        schema_format: @schema_format,
        data_format: @data_format
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
        signature_class_name: hash[:signature_class_name],
        schema_format: hash[:schema_format] || :json,
        data_format: hash[:data_format] || :json
      )
    end

    # Create prompt from signature class
    sig do
      params(
        signature_class: T.class_of(Signature),
        schema_format: T.nilable(Symbol),
        data_format: T.nilable(Symbol)
      ).returns(Prompt)
    end
    def self.from_signature(signature_class, schema_format: nil, data_format: nil)
      new(
        instruction: signature_class.description || "Complete this task.",
        input_schema: signature_class.input_json_schema,
        output_schema: signature_class.output_json_schema,
        few_shot_examples: [],
        signature_class_name: signature_class.name,
        schema_format: schema_format,
        signature_class: signature_class,
        data_format: data_format
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

    # Render BAML schema for input or output
    sig { params(schema: T::Hash[Symbol, T.untyped], type: Symbol).returns(String) }
    def render_baml_schema(schema, type)
      # If we have a signature_class, use sorbet-baml's to_baml method with custom name
      if @signature_class
        begin
          require 'sorbet_baml'

          struct_class = type == :input ? @signature_class.input_struct_class : @signature_class.output_struct_class
          if struct_class
            # Generate a proper class name from signature class name
            base_name = @signature_class_name || @signature_class.name || "Schema"
            class_name = type == :input ? "#{base_name}Input" : "#{base_name}Output"

            # Get raw BAML and replace the ugly class name
            raw_baml = struct_class.to_baml
            # Replace the class definition line with a proper name
            return raw_baml.sub(/^class #<Class:0x[0-9a-f]+>/, "class #{class_name}")
          end
        rescue LoadError
          # Fall back to manual BAML generation if sorbet_baml is not available
        end
      end

      # Fallback: generate BAML manually from schema
      # This is a simple implementation that handles basic types
      # For production use, sorbet-baml should be available
      "# BAML schema generation requires sorbet-baml gem\n" \
      "# Please install: gem install sorbet-baml"
    end

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

    def toon_data_format_enabled?
      data_format == :toon && @signature_class
    end

    SAMPLE_DEPTH_LIMIT = 3
    private_constant :SAMPLE_DEPTH_LIMIT

    def example_toon_payload(role)
      return nil unless toon_data_format_enabled?

      sample_values = case role
                      when :input
                        sample_struct_values(@signature_class.input_struct_class)
                      when :output
                        sample_struct_values(@signature_class.output_struct_class)
                      else
                        {}
                      end

      return nil if sample_values.empty?

      case role
      when :input
        DSPy::Schema::SorbetToonAdapter.render_input(@signature_class, sample_values)
      when :output
        DSPy::Schema::SorbetToonAdapter.render_expected_output(@signature_class, sample_values)
      end
    rescue StandardError
      nil
    end

    def sample_struct_values(struct_class, depth = 0)
      return {} unless struct_class&.respond_to?(:props)
      struct_class.props.each_with_object({}) do |(name, prop_info), memo|
        memo[name] = sample_value_for_type(prop_info[:type], name, depth)
      end
    end

    def sample_value_for_type(prop_type, field_name, depth)
      return sample_string(field_name) if prop_type.nil? || depth > SAMPLE_DEPTH_LIMIT

      case prop_type
      when T::Types::Simple
        sample_value_for_type(prop_type.raw_type, field_name, depth + 1)
      when T::Types::Union
        preferred = prop_type.types.find { |type| !nil_type?(type) } || prop_type.types.first
        sample_value_for_type(preferred, field_name, depth + 1)
      when T::Types::TypedArray
        [sample_value_for_type(prop_type.type, field_name, depth + 1)]
      when T::Types::TypedHash
        key_sample = sample_value_for_type(prop_type.keys, "#{field_name}_key", depth + 1)
        value_sample = sample_value_for_type(prop_type.values, "#{field_name}_value", depth + 1)
        { key_sample.to_s => value_sample }
      when Class
        sample_for_class_type(prop_type, field_name, depth)
      else
        sample_string(field_name)
      end
    end

    def sample_for_class_type(prop_type, field_name, depth)
      if prop_type <= String
        sample_string(field_name)
      elsif prop_type <= Integer
        1
      elsif prop_type <= Float
        1.0
      elsif prop_type <= Numeric
        1
      elsif prop_type <= TrueClass || prop_type <= FalseClass
        true
      elsif prop_type <= T::Enum
        enum_value = prop_type.values.first
        enum_value ? enum_value.serialize : sample_string(field_name)
      elsif prop_type <= T::Struct
        sample_struct_values(prop_type, depth + 1)
      else
        sample_string(field_name)
      end
    end

    def nil_type?(type)
      (type.respond_to?(:raw_type) && type.raw_type == NilClass) || type == NilClass
    end

    def sample_string(field_name)
      base = field_name.to_s.gsub(/[^a-z0-9]+/i, '_').gsub(/_{2,}/, '_').sub(/^_+|_+$/, '')
      base = 'value' if base.empty?
      "example_#{base}"
    end

    def resolve_schema_format(schema_format)
      return schema_format unless schema_format.nil?

      lm = DSPy.respond_to?(:current_lm) ? DSPy.current_lm : DSPy.config.lm
      lm&.schema_format || :json
    end

    def resolve_data_format(data_format)
      return data_format unless data_format.nil?

      lm = DSPy.respond_to?(:current_lm) ? DSPy.current_lm : DSPy.config.lm
      lm_format = lm&.respond_to?(:data_format) ? lm.data_format : nil
      lm_format || :json
    end
  end
end
