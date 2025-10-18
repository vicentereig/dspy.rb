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

      MAX_HISTORY_INSTRUCTIONS = 5

      # Python-compatible TIPS dictionary for instruction generation
      TIPS = {
        "none" => "",
        "creative" => "Don't be afraid to be creative when creating the new instruction!",
        "simple" => "Keep the instruction clear and concise.",
        "description" => "Make sure your instruction is very informative and descriptive.",
        "high_stakes" => "The instruction should include a high stakes scenario in which the LM must solve the task!",
        "persona" => 'Include a persona that is relevant to the task in the instruction (ie. "You are a ...")'
      }.freeze

      # Configuration for instruction proposal (Python-compatible)
      class Config
        extend T::Sig

        # Core parameters
        sig { returns(Integer) }
        attr_accessor :num_instruction_candidates

        # Python-compatible awareness flags (match Python defaults exactly)
        sig { returns(T::Boolean) }
        attr_accessor :program_aware

        sig { returns(T::Boolean) }
        attr_accessor :use_dataset_summary

        sig { returns(T::Boolean) }
        attr_accessor :use_task_demos

        sig { returns(T::Boolean) }
        attr_accessor :use_tip

        sig { returns(T::Boolean) }
        attr_accessor :use_instruct_history

        # Additional parameters
        sig { returns(Integer) }
        attr_accessor :view_data_batch_size

        sig { returns(Integer) }
        attr_accessor :num_demos_in_context

        sig { returns(T::Boolean) }
        attr_accessor :set_tip_randomly

        sig { returns(T::Boolean) }
        attr_accessor :set_history_randomly

        sig { returns(Float) }
        attr_accessor :init_temperature

        sig { returns(T::Boolean) }
        attr_accessor :verbose

        sig { void }
        def initialize
          # Core parameters
          @num_instruction_candidates = 5

          # Python-compatible awareness flags (match Python defaults)
          @program_aware = true
          @use_dataset_summary = true
          @use_task_demos = true
          @use_tip = true
          @use_instruct_history = true

          # Additional parameters
          @view_data_batch_size = 10
          @num_demos_in_context = 3
          @set_tip_randomly = true
          @set_history_randomly = true
          @init_temperature = 1.0
          @verbose = false
        end
      end

      # Result of instruction proposal
      class ProposalResult
        extend T::Sig

        sig { returns(T::Array[String]) }
        attr_reader :candidate_instructions

        sig { returns(T::Hash[Integer, T::Array[String]]) }
        attr_reader :predictor_instructions

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :analysis

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :metadata

        sig do
          params(
            candidate_instructions: T::Array[String],
            analysis: T::Hash[Symbol, T.untyped],
            metadata: T::Hash[Symbol, T.untyped],
            predictor_instructions: T.nilable(T::Hash[Integer, T::Array[String]])
          ).void
        end
        def initialize(candidate_instructions:, analysis:, metadata:, predictor_instructions: nil)
          @candidate_instructions = candidate_instructions.freeze
        normalized_predictor_instructions = (predictor_instructions || {}).each_with_object({}) do |(index, instructions), memo|
            memo[index] = instructions.dup.freeze
          end
          @predictor_instructions = normalized_predictor_instructions.freeze
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

      sig do
        params(
          config: T.nilable(Config),
          program: T.nilable(T.untyped),
          trainset: T.nilable(T::Array[DSPy::Example])
        ).void
      end
      def initialize(config: nil, program: nil, trainset: nil)
        @config = config || Config.new
        @program = program
        @trainset = trainset
        @dataset_summary = nil
        @program_code_string = nil

        # Generate dataset summary if data-aware mode enabled (Python: use_dataset_summary)
        if @config.use_dataset_summary && trainset && !trainset.empty?
          begin
            require_relative 'dataset_summary_generator'
            @dataset_summary = DatasetSummaryGenerator.create_dataset_summary(
              trainset,
              @config.view_data_batch_size,
              DSPy.current_lm,
              verbose: @config.verbose
            )
          rescue => e
            DSPy.logger.warn("Failed to generate dataset summary: #{e.message}")
            @dataset_summary = nil
          end
        end

        # Extract program source code if program-aware mode enabled
        if @config.program_aware && program
          @program_code_string = extract_program_source(program)
        end
      end

      private

      # Extract source code from program for program-aware mode
      sig { params(program: T.untyped).returns(T.nilable(String)) }
      def extract_program_source(program)
        # Get the program's class
        klass = program.is_a?(Class) ? program : program.class

        # Try to get source location
        source_location = klass.instance_method(:forward).source_location rescue nil
        return nil unless source_location

        file, line = source_location
        # Read the source file and extract the class definition
        # This is a simplified version - could be enhanced with method_source gem
        code = "Program: #{klass.name}\nSource: #{file}:#{line}"
        code
      rescue => e
        DSPy.logger.warn("Could not extract program source: #{e.message}")
        nil
      end

      public

      # Generate instruction candidates for a signature and training examples
      sig do
        params(
          signature_class: T.class_of(DSPy::Signature),
          examples: T::Array[T.untyped],
          few_shot_examples: T.nilable(T::Array[T.untyped]),
          current_instruction: T.nilable(String),
          trial_logs: T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]])
        ).returns(ProposalResult)
      end
      def propose_instructions(signature_class, examples, few_shot_examples: nil, current_instruction: nil, trial_logs: nil)
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
            current_instruction,
            few_shot_examples: few_shot_examples,
            trial_logs: trial_logs
          )

          # Filter and rank candidates
          filtered_candidates = filter_and_rank_candidates(candidates, analysis)

          metadata = {
            generation_timestamp: Time.now.iso8601,
            model_used: DSPy.current_lm.model,
            num_examples_analyzed: [examples.size, @config.view_data_batch_size].min,
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

      sig do
        params(
          trainset: T::Array[T.untyped],
          program: T.untyped,
          demo_candidates: T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]],
          trial_logs: T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]]),
          num_instruction_candidates: T.nilable(Integer)
        ).returns(ProposalResult)
      end
      def propose_instructions_for_program(trainset:, program:, demo_candidates:, trial_logs: nil, num_instruction_candidates: nil)
        num_candidates = num_instruction_candidates || @config.num_instruction_candidates

        current_instruction = if program.respond_to?(:prompt) && program.prompt.respond_to?(:instruction)
          program.prompt.instruction
        else
          nil
        end

        few_shot_examples = demo_candidates[0]&.flatten&.take(@config.num_demos_in_context) || []

        signature_class = if program.respond_to?(:signature_class)
          program.signature_class
        else
          raise ArgumentError, "Program must expose signature_class for instruction proposal"
        end

        base_result = propose_instructions(
          signature_class,
          trainset,
          few_shot_examples: few_shot_examples,
          current_instruction: current_instruction,
          trial_logs: trial_logs
        )

        predictor_instructions = { 0 => base_result.candidate_instructions.take(num_candidates) }

        ProposalResult.new(
          candidate_instructions: base_result.candidate_instructions,
          analysis: base_result.analysis,
          metadata: base_result.metadata,
          predictor_instructions: predictor_instructions
        )
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
        analysis_examples = examples.take(@config.view_data_batch_size)
        
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
          current_instruction: T.nilable(String),
          few_shot_examples: T.nilable(T::Array[T.untyped]),
          trial_logs: T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]])
        ).returns(T::Array[String])
      end
      def generate_instruction_candidates(signature_class, analysis, current_instruction, few_shot_examples: nil, trial_logs: nil)
        # Build context for instruction generation
        context = build_generation_context(
          signature_class,
          analysis,
          current_instruction,
          few_shot_examples: few_shot_examples,
          trial_logs: trial_logs
        )
        
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
          current_instruction: T.nilable(String),
          few_shot_examples: T.nilable(T::Array[T.untyped]),
          trial_logs: T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]])
        ).returns(String)
      end
      def build_generation_context(signature_class, analysis, current_instruction, few_shot_examples: nil, trial_logs: nil)
        context_parts = []

        # Include dataset summary if enabled and available
        if @config.use_dataset_summary && @dataset_summary
          context_parts << "Dataset Summary: #{@dataset_summary}"
        end

        # Include program code if enabled and available
        if @config.program_aware && @program_code_string
          context_parts << "Program Code:\n#{@program_code_string}"
        end

        # Always include task description (fundamental to understanding the task)
        context_parts << "Task: #{signature_class.description}"

        # Always include field analysis (fundamental to understanding inputs/outputs)
        input_descriptions = analysis[:input_fields].map { |f| format_field_description(f) }
        output_descriptions = analysis[:output_fields].map { |f| format_field_description(f) }

        context_parts << "Input fields: #{input_descriptions.join(', ')}"
        context_parts << "Output fields: #{output_descriptions.join(', ')}"

        # Include task demos if enabled and available
        if @config.use_task_demos && few_shot_examples && !few_shot_examples.empty?
          demo_strings = few_shot_examples.take(@config.num_demos_in_context).map do |example|
            format_example_as_demo(example)
          end
          context_parts << "Task Demos:\n#{demo_strings.join("\n\n")}"
        end

        if analysis[:common_themes] && analysis[:common_themes].any?
          context_parts << "Task themes: #{analysis[:common_themes].join(', ')}"
        end

        if current_instruction
          context_parts << "Current instruction: \"#{current_instruction}\""
        end

        # Include tip if enabled
        if @config.use_tip
          tip = select_tip
          context_parts << "Tip: #{tip}" if tip && !tip.empty?
        end

        if @config.use_instruct_history
          history_summary = build_instruction_history_summary(trial_logs, predictor_index: 0, top_n: MAX_HISTORY_INSTRUCTIONS)
          unless history_summary.empty?
            context_parts << "Previous instructions:\n#{history_summary}"
          end
        end

        context_parts.join("\n\n")
      end

      # Format field description with enum values if applicable
      sig { params(field: T::Hash[Symbol, T.untyped]).returns(String) }
      def format_field_description(field)
        base = "#{field[:name]} (#{field[:type]})"
        if field[:is_enum] && field[:enum_values] && !field[:enum_values].empty?
          "#{base} [values: #{field[:enum_values].join(', ')}]"
        else
          base
        end
      end

      # Format an example as a demo for context
      sig { params(example: T.untyped).returns(String) }
      def format_example_as_demo(example)
        return example.to_s unless example.respond_to?(:inputs) && example.respond_to?(:expected)

        parts = []

        # Format inputs
        if example.inputs && !example.inputs.empty?
          input_strs = example.inputs.map { |k, v| "#{k}: #{v.inspect}" }
          parts << "Inputs: #{input_strs.join(', ')}"
        end

        # Format expected outputs
        if example.expected && !example.expected.empty?
          output_strs = example.expected.map { |k, v| "#{k}: #{v.inspect}" }
          parts << "Expected: #{output_strs.join(', ')}"
        end

        parts.join(" | ")
      end

      # Select a tip based on configuration
      sig { returns(T.nilable(String)) }
      def select_tip
        if @config.set_tip_randomly
          # Randomly select a tip (excluding "none")
          tip_keys = TIPS.keys.reject { |k| k == "none" }
          selected_key = tip_keys.sample
          TIPS[selected_key]
        else
          # Return empty string when not using random tips
          ""
        end
      end

      sig do
        params(
          trial_logs: T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]]),
          predictor_index: Integer,
          top_n: Integer
        ).returns(String)
      end
      def build_instruction_history_summary(trial_logs, predictor_index:, top_n:)
        return "" unless @config.use_instruct_history

        logs = trial_logs || {}
        aggregate = Hash.new { |hash, key| hash[key] = { total: 0.0, count: 0 } }

        logs.each_value do |entry|
          score = entry[:score]
          next unless score.respond_to?(:to_f)

          instructions = entry[:instructions]
          instruction = nil
          if instructions.respond_to?(:[])
            instruction = instructions[predictor_index] || instructions[:default]
          end
          instruction ||= entry[:instruction]

          next unless instruction.is_a?(String) && !instruction.empty?

          aggregate[instruction][:total] += score.to_f
          aggregate[instruction][:count] += 1
        end

        return "" if aggregate.empty?

        ranked = aggregate.map do |instruction, stats|
          average = stats[:total] / stats[:count]
          [instruction, average]
        end

        top_entries = ranked.sort_by { |(_, avg)| -avg }.take(top_n).reverse
        top_entries.map { |instruction, avg| format("%s | Score: %.4f", instruction, avg) }.join("\n\n")
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
        
        # Simple ranking based on content quality (Python-compatible: no length scoring)
        filtered.sort_by do |instruction|
          score = 0

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
          'proposal.model_used' => DSPy.current_lm.model
        })
      end
    end
  end
end
