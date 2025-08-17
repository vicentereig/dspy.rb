# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../signature'
require_relative '../predict'

module DSPy
  module Propose
    # Grounded Proposer for generating better instructions based on training data
    # Analyzes task patterns and creates contextually appropriate instructions
    class GroundedProposer
      extend T::Sig

      # Configuration for instruction proposal
      class Config
        extend T::Sig

        sig { returns(Integer) }
        attr_accessor :num_instruction_candidates

        sig { returns(Integer) }
        attr_accessor :max_examples_for_analysis

        sig { returns(Integer) }
        attr_accessor :max_instruction_length

        sig { returns(T::Boolean) }
        attr_accessor :use_task_description

        sig { returns(T::Boolean) }
        attr_accessor :use_input_output_analysis

        sig { returns(T::Boolean) }
        attr_accessor :use_few_shot_examples

        sig { returns(String) }
        attr_accessor :proposal_model

        sig { void }
        def initialize
          @num_instruction_candidates = 5
          @max_examples_for_analysis = 10
          @max_instruction_length = 200
          @use_task_description = true
          @use_input_output_analysis = true
          @use_few_shot_examples = true
          @proposal_model = "gpt-4o-mini"
        end
      end

      # Result of instruction proposal
      class ProposalResult
        extend T::Sig

        sig { returns(T::Array[String]) }
        attr_reader :candidate_instructions

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :analysis

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :metadata

        sig do
          params(
            candidate_instructions: T::Array[String],
            analysis: T::Hash[Symbol, T.untyped],
            metadata: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(candidate_instructions:, analysis:, metadata:)
          @candidate_instructions = candidate_instructions.freeze
          @analysis = analysis.freeze
          @metadata = metadata.freeze
        end

        sig { returns(String) }
        def best_instruction
          @candidate_instructions.first || ""
        end

        sig { returns(Integer) }
        def num_candidates
          @candidate_instructions.size
        end
      end

      sig { returns(Config) }
      attr_reader :config

      sig { params(config: T.nilable(Config)).void }
      def initialize(config: nil)
        @config = config || Config.new
      end

      # Generate instruction candidates for a signature and training examples
      sig do
        params(
          signature_class: T.class_of(DSPy::Signature),
          examples: T::Array[T.untyped],
          few_shot_examples: T.nilable(T::Array[T.untyped]),
          current_instruction: T.nilable(String)
        ).returns(ProposalResult)
      end
      def propose_instructions(signature_class, examples, few_shot_examples: nil, current_instruction: nil)
        DSPy::Context.with_span(
          operation: 'optimization.instruction_proposal',
          'dspy.module' => 'GroundedProposer',
          'proposal.signature' => signature_class.name,
          'proposal.num_examples' => examples.size,
          'proposal.has_few_shot' => !few_shot_examples.nil?,
          'proposal.has_current_instruction' => !current_instruction.nil?
        ) do
          # Analyze the task and training data
          analysis = analyze_task(signature_class, examples, few_shot_examples)
          
          # Generate instruction candidates
          candidates = generate_instruction_candidates(
            signature_class, 
            analysis, 
            current_instruction
          )

          # Filter and rank candidates
          filtered_candidates = filter_and_rank_candidates(candidates, analysis)

          metadata = {
            generation_timestamp: Time.now.iso8601,
            model_used: @config.proposal_model,
            num_examples_analyzed: [examples.size, @config.max_examples_for_analysis].min,
            original_instruction: current_instruction
          }

          result = ProposalResult.new(
            candidate_instructions: filtered_candidates,
            analysis: analysis,
            metadata: metadata
          )

          emit_proposal_complete_event(result)
          result
        end
      end

      private

      # Analyze the task based on signature and training examples
      sig do
        params(
          signature_class: T.class_of(DSPy::Signature),
          examples: T::Array[T.untyped],
          few_shot_examples: T.nilable(T::Array[T.untyped])
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def analyze_task(signature_class, examples, few_shot_examples)
        analysis = {
          task_description: signature_class.description,
          input_fields: extract_field_info(signature_class.input_struct_class),
          output_fields: extract_field_info(signature_class.output_struct_class),
          example_patterns: analyze_example_patterns(examples),
          complexity_indicators: assess_task_complexity(signature_class, examples)
        }

        if few_shot_examples && few_shot_examples.any?
          analysis[:few_shot_patterns] = analyze_few_shot_patterns(few_shot_examples)
        end

        analysis
      end

      # Extract field information from struct classes
      sig { params(struct_class: T.class_of(T::Struct)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def extract_field_info(struct_class)
        struct_class.props.map do |name, prop_info|
          field_info = {
            name: name,
            type: prop_info[:type].to_s,
            description: prop_info[:description] || "",
            required: !prop_info[:rules]&.any? { |rule| rule.is_a?(T::Props::NilableRules) }
          }
          
          # Extract enum values if this is an enum type
          if enum_values = extract_enum_values(prop_info[:type])
            field_info[:enum_values] = enum_values
            field_info[:is_enum] = true
          end
          
          field_info
        end
      end

      # Extract enum values from a type if it's an enum
      sig { params(type: T.untyped).returns(T.nilable(T::Array[String])) }
      def extract_enum_values(type)
        # Handle T::Enum types
        if type.is_a?(Class) && type < T::Enum
          type.values.map(&:serialize)
        else
          nil
        end
      end


      # Analyze patterns in training examples
      sig { params(examples: T::Array[T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def analyze_example_patterns(examples)
        analysis_examples = examples.take(@config.max_examples_for_analysis)
        
        {
          total_examples: examples.size,
          analyzed_examples: analysis_examples.size,
          input_patterns: analyze_input_patterns(analysis_examples),
          output_patterns: analyze_output_patterns(analysis_examples),
          common_themes: extract_common_themes(analysis_examples)
        }
      end

      # Analyze input patterns in examples
      sig { params(examples: T::Array[T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def analyze_input_patterns(examples)
        input_lengths = []
        input_types = []
        common_keywords = Hash.new(0)

        examples.each do |example|
          input_values = extract_input_values(example)
          
          input_values.each do |key, value|
            if value.is_a?(String)
              input_lengths << value.length
              # Extract potential keywords
              value.downcase.split(/\W+/).each { |word| common_keywords[word] += 1 if word.length > 3 }
            end
            input_types << value.class.name
          end
        end

        {
          avg_input_length: input_lengths.empty? ? 0 : input_lengths.sum.to_f / input_lengths.size,
          common_input_types: input_types.tally,
          frequent_keywords: common_keywords.sort_by { |_, count| -count }.take(10).to_h
        }
      end

      # Analyze output patterns in examples
      sig { params(examples: T::Array[T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def analyze_output_patterns(examples)
        output_lengths = []
        output_types = []

        examples.each do |example|
          expected_values = extract_expected_values(example)
          
          expected_values.each do |key, value|
            if value.is_a?(String)
              output_lengths << value.length
            end
            output_types << value.class.name
          end
        end

        {
          avg_output_length: output_lengths.empty? ? 0 : output_lengths.sum.to_f / output_lengths.size,
          common_output_types: output_types.tally
        }
      end

      # Extract common themes from examples
      sig { params(examples: T::Array[T.untyped]).returns(T::Array[String]) }
      def extract_common_themes(examples)
        themes = []
        
        # Simple heuristics for theme detection
        input_texts = examples.map { |ex| extract_input_values(ex).values.select { |v| v.is_a?(String) } }.flatten
        
        if input_texts.any? { |text| text.downcase.include?("question") || text.include?("?") }
          themes << "question_answering"
        end
        
        if input_texts.any? { |text| text.downcase.match?(/\b(classify|category|type)\b/) }
          themes << "classification"
        end
        
        if input_texts.any? { |text| text.match?(/\d+.*[+\-*\/].*\d+/) }
          themes << "mathematical_reasoning"
        end
        
        if input_texts.any? { |text| text.downcase.match?(/\b(analyze|explain|reason)\b/) }
          themes << "analytical_reasoning"
        end

        themes
      end

      # Analyze few-shot example patterns
      sig { params(few_shot_examples: T::Array[T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def analyze_few_shot_patterns(few_shot_examples)
        {
          num_examples: few_shot_examples.size,
          demonstrates_reasoning: few_shot_examples.any? { |ex| has_reasoning_field?(ex) },
          example_variety: assess_example_variety(few_shot_examples)
        }
      end

      # Assess task complexity indicators
      sig do
        params(
          signature_class: T.class_of(DSPy::Signature),
          examples: T::Array[T.untyped]
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def assess_task_complexity(signature_class, examples)
        {
          num_input_fields: signature_class.input_struct_class.props.size,
          num_output_fields: signature_class.output_struct_class.props.size,
          has_complex_outputs: has_complex_output_types?(signature_class),
          requires_reasoning: task_requires_reasoning?(signature_class, examples)
        }
      end

      # Generate instruction candidates using LLM
      sig do
        params(
          signature_class: T.class_of(DSPy::Signature),
          analysis: T::Hash[Symbol, T.untyped],
          current_instruction: T.nilable(String)
        ).returns(T::Array[String])
      end
      def generate_instruction_candidates(signature_class, analysis, current_instruction)
        # Build context for instruction generation
        context = build_generation_context(signature_class, analysis, current_instruction)
        
        # Create instruction generation signature
        instruction_signature = create_instruction_generation_signature
        
        # Generate candidates using LLM
        generator = DSPy::Predict.new(instruction_signature)
        
        candidates = []
        @config.num_instruction_candidates.times do |i|
          begin
            result = generator.call(
              task_context: context,
              requirements: build_requirements_text(analysis),
              candidate_number: i + 1
            )
            
            instruction = result.instruction.strip
            
            # Truncate if too long
            if instruction.length > @config.max_instruction_length
              instruction = instruction[0, @config.max_instruction_length].strip
              # Try to end at a word boundary
              if instruction.include?(' ')
                instruction = instruction.rpartition(' ').first + '.'
              end
            end
            
            candidates << instruction if instruction.length > 0
          rescue => error
            DSPy.logger.warn("Failed to generate instruction candidate #{i + 1}: #{error.message}")
          end
        end

        # Ensure we have at least one candidate
        if candidates.empty?
          candidates << generate_fallback_instruction(signature_class, analysis)
        end

        candidates.uniq
      end

      # Build context for instruction generation
      sig do
        params(
          signature_class: T.class_of(DSPy::Signature),
          analysis: T::Hash[Symbol, T.untyped],
          current_instruction: T.nilable(String)
        ).returns(String)
      end
      def build_generation_context(signature_class, analysis, current_instruction)
        context_parts = []
        
        context_parts << "Task: #{signature_class.description}" if @config.use_task_description
        
        if @config.use_input_output_analysis
          # Build detailed field descriptions including enum values
          input_descriptions = analysis[:input_fields].map { |f| format_field_description(f) }
          output_descriptions = analysis[:output_fields].map { |f| format_field_description(f) }
          
          context_parts << "Input fields: #{input_descriptions.join(', ')}"
          context_parts << "Output fields: #{output_descriptions.join(', ')}"
        end
        
        if analysis[:common_themes] && analysis[:common_themes].any?
          context_parts << "Task themes: #{analysis[:common_themes].join(', ')}"
        end
        
        if current_instruction
          context_parts << "Current instruction: \"#{current_instruction}\""
        end
        
        context_parts.join("\n")
      end

      # Format field description with enum values if applicable
      sig { params(field: T::Hash[Symbol, T.untyped]).returns(String) }
      def format_field_description(field)
        base = "#{field[:name]} (#{field[:type]})"
        if field[:is_enum] && field[:enum_values]
          "#{base} [values: #{field[:enum_values].join(', ')}]"
        else
          base
        end
      end

      # Build requirements text for instruction generation
      sig { params(analysis: T::Hash[Symbol, T.untyped]).returns(String) }
      def build_requirements_text(analysis)
        requirements = []
        
        requirements << "Be specific and actionable"
        requirements << "Guide the model's reasoning process"
        
        if analysis[:complexity_indicators][:requires_reasoning]
          requirements << "Encourage step-by-step thinking"
        end
        
        if analysis[:common_themes]&.include?("mathematical_reasoning")
          requirements << "Emphasize mathematical accuracy"
        end
        
        if analysis[:common_themes]&.include?("classification")
          requirements << "Encourage careful categorization"
        end
        
        requirements.join(". ") + "."
      end

      # Create signature for instruction generation
      sig { returns(T.class_of(DSPy::Signature)) }
      def create_instruction_generation_signature
        Class.new(DSPy::Signature) do
          description "Generate an improved instruction for a language model task"
          
          input do
            const :task_context, String, description: "Context about the task and current setup"
            const :requirements, String, description: "Requirements for the instruction"
            const :candidate_number, Integer, description: "Which candidate this is (for variety)"
          end
          
          output do
            const :instruction, String, description: "A clear, specific instruction for the task"
          end
        end
      end

      # Generate a fallback instruction when LLM generation fails
      sig do
        params(
          signature_class: T.class_of(DSPy::Signature),
          analysis: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def generate_fallback_instruction(signature_class, analysis)
        base = signature_class.description || "Complete the given task"
        
        if analysis[:complexity_indicators][:requires_reasoning]
          "#{base} Think step by step and provide a clear explanation."
        else
          "#{base} Be accurate and specific in your response."
        end
      end

      # Filter and rank instruction candidates
      sig { params(candidates: T::Array[String], analysis: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
      def filter_and_rank_candidates(candidates, analysis)
        # Filter out duplicates and empty candidates
        filtered = candidates.uniq.reject(&:empty?)
        
        # Simple ranking based on length and content quality
        filtered.sort_by do |instruction|
          score = 0
          
          # Prefer moderate length instructions
          length_score = [instruction.length, @config.max_instruction_length].min / @config.max_instruction_length.to_f
          score += length_score * 0.3
          
          # Prefer instructions with action words
          action_words = %w[analyze classify generate explain solve determine identify]
          action_score = action_words.count { |word| instruction.downcase.include?(word) }
          score += action_score * 0.4
          
          # Prefer instructions that mention reasoning for complex tasks
          if analysis[:complexity_indicators][:requires_reasoning]
            reasoning_score = instruction.downcase.match?(/\b(step|think|reason|explain)\b/) ? 1 : 0
            score += reasoning_score * 0.3
          end
          
          -score # Negative for descending sort
        end
      end

      # Helper methods for extracting values from examples
      sig { params(example: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def extract_input_values(example)
        case example
        when DSPy::Example
          example.input_values
        when Hash
          example[:input] || example.select { |k, _| k != :expected && k != :output }
        else
          example.respond_to?(:input) ? example.input : {}
        end
      end

      sig { params(example: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def extract_expected_values(example)
        case example
        when DSPy::Example
          example.expected_values
        when Hash
          example[:expected] || example[:output] || {}
        else
          example.respond_to?(:expected) ? example.expected : {}
        end
      end

      # Check if example has reasoning field
      sig { params(example: T.untyped).returns(T::Boolean) }
      def has_reasoning_field?(example)
        values = extract_expected_values(example)
        values.key?(:reasoning) || values.key?(:explanation) || values.key?(:rationale)
      end

      # Assess variety in examples
      sig { params(examples: T::Array[T.untyped]).returns(String) }
      def assess_example_variety(examples)
        return "low" if examples.size < 3
        
        # Simple heuristic based on input diversity
        input_patterns = examples.map { |ex| extract_input_values(ex).values.map(&:to_s).join(" ") }
        unique_patterns = input_patterns.uniq.size
        
        variety_ratio = unique_patterns.to_f / examples.size
        
        case variety_ratio
        when 0.8..1.0 then "high"
        when 0.5..0.8 then "medium"
        else "low"
        end
      end

      # Check if signature has complex output types
      sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T::Boolean) }
      def has_complex_output_types?(signature_class)
        signature_class.output_struct_class.props.any? do |_, prop_info|
          type_str = prop_info[:type].to_s
          type_str.include?("Array") || type_str.include?("Hash") || type_str.include?("T::Enum")
        end
      end

      # Check if task requires reasoning
      sig { params(signature_class: T.class_of(DSPy::Signature), examples: T::Array[T.untyped]).returns(T::Boolean) }
      def task_requires_reasoning?(signature_class, examples)
        # Check if output has reasoning fields
        has_reasoning_outputs = signature_class.output_struct_class.props.any? do |name, _|
          name.to_s.match?(/reason|explain|rational|justif/i)
        end
        
        return true if has_reasoning_outputs
        
        # Check if examples suggest reasoning is needed
        sample_examples = examples.take(5)
        requires_reasoning = sample_examples.any? do |example|
          input_values = extract_input_values(example)
          input_text = input_values.values.select { |v| v.is_a?(String) }.join(" ")
          input_text.downcase.match?(/\b(why|how|explain|analyze|reason)\b/)
        end
        
        requires_reasoning
      end

      # Emit instruction proposal completion event
      sig { params(result: ProposalResult).void }
      def emit_proposal_complete_event(result)
        DSPy.log('optimization.instruction_proposal_complete', **{
          'proposal.num_candidates' => result.num_candidates,
          'proposal.best_instruction_length' => result.best_instruction.length,
          'proposal.analysis_themes' => result.analysis[:common_themes] || [],
          'proposal.model_used' => @config.proposal_model
        })
      end
    end
  end
end