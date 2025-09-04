# frozen_string_literal: true

require 'ostruct'
require 'sorbet-runtime'
require_relative 'teleprompter'

module DSPy
  module Teleprompt
    # GEPA: Genetic-Pareto Reflective Prompt Evolution optimizer
    # Uses natural language reflection to evolve prompts through genetic algorithms
    # and Pareto frontier selection for maintaining diverse high-performing candidates
    class GEPA < Teleprompter
      extend T::Sig

      # Immutable execution trace record using Ruby's Data class
      # Captures execution events for GEPA's reflective analysis
      class ExecutionTrace < Data.define(
        :trace_id,
        :event_name,
        :timestamp,
        :span_id,
        :attributes,
        :metadata
      )
        extend T::Sig

        # Type aliases for better type safety
        AttributesHash = T.type_alias { T::Hash[T.any(String, Symbol), T.untyped] }
        MetadataHash = T.type_alias { T::Hash[Symbol, T.untyped] }

        sig do
          params(
            trace_id: String,
            event_name: String,
            timestamp: Time,
            span_id: T.nilable(String),
            attributes: AttributesHash,
            metadata: T.nilable(MetadataHash)
          ).void
        end
        def initialize(trace_id:, event_name:, timestamp:, span_id: nil, attributes: {}, metadata: nil)
          # Freeze nested structures for true immutability
          frozen_attributes = attributes.freeze
          frozen_metadata = metadata&.freeze

          super(
            trace_id: trace_id,
            event_name: event_name,
            timestamp: timestamp,
            span_id: span_id,
            attributes: frozen_attributes,
            metadata: frozen_metadata
          )
        end

        # Check if this is an LLM-related trace
        sig { returns(T::Boolean) }
        def llm_trace?
          event_name.start_with?('llm.') || event_name.start_with?('lm.')
        end

        # Check if this is a module-related trace
        sig { returns(T::Boolean) }
        def module_trace?
          !llm_trace? && (
            event_name.include?('chain_of_thought') ||
            event_name.include?('react') ||
            event_name.include?('codeact') ||
            event_name.include?('predict')
          )
        end

        # Extract token usage from LLM traces
        sig { returns(Integer) }
        def token_usage
          return 0 unless llm_trace?

          # Try different token attribute keys
          [
            'gen_ai.usage.total_tokens',
            'gen_ai.usage.prompt_tokens',
            'tokens',
            :tokens
          ].each do |key|
            value = attributes[key]
            return value.to_i if value
          end

          0
        end

        # Convert to hash representation
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            trace_id: trace_id,
            event_name: event_name,
            timestamp: timestamp,
            span_id: span_id,
            attributes: attributes,
            metadata: metadata
          }
        end

        # Extract prompt text from trace
        sig { returns(T.nilable(String)) }
        def prompt_text
          attributes[:prompt] || attributes['prompt']
        end

        # Extract response text from trace
        sig { returns(T.nilable(String)) }
        def response_text
          attributes[:response] || attributes['response']
        end

        # Get the model used in this trace
        sig { returns(T.nilable(String)) }
        def model_name
          attributes['gen_ai.request.model'] || attributes[:model]
        end

        # Get the signature class name
        sig { returns(T.nilable(String)) }
        def signature_name
          attributes['dspy.signature'] || attributes[:signature]
        end
      end

      # Immutable reflection analysis result using Ruby's Data class
      # Stores the output of GEPA's reflective analysis on execution traces
      class ReflectionResult < Data.define(
        :trace_id,
        :diagnosis,
        :improvements,
        :confidence,
        :reasoning,
        :suggested_mutations,
        :metadata
      )
        extend T::Sig

        # Type aliases for better type safety
        ImprovementsList = T.type_alias { T::Array[String] }
        MutationsList = T.type_alias { T::Array[Symbol] }
        MetadataHash = T.type_alias { T::Hash[Symbol, T.untyped] }

        sig do
          params(
            trace_id: String,
            diagnosis: String,
            improvements: ImprovementsList,
            confidence: Float,
            reasoning: String,
            suggested_mutations: MutationsList,
            metadata: MetadataHash
          ).void
        end
        def initialize(trace_id:, diagnosis:, improvements:, confidence:, reasoning:, suggested_mutations:, metadata:)
          # Validate confidence score
          if confidence < 0.0 || confidence > 1.0
            raise ArgumentError, "confidence must be between 0 and 1, got #{confidence}"
          end

          # Freeze nested structures for true immutability
          frozen_improvements = improvements.freeze
          frozen_mutations = suggested_mutations.freeze
          frozen_metadata = metadata.freeze

          super(
            trace_id: trace_id,
            diagnosis: diagnosis,
            improvements: frozen_improvements,
            confidence: confidence,
            reasoning: reasoning,
            suggested_mutations: frozen_mutations,
            metadata: frozen_metadata
          )
        end

        # Check if this reflection has high confidence (>= 0.8)
        sig { returns(T::Boolean) }
        def high_confidence?
          confidence >= 0.8
        end

        # Check if this reflection suggests actionable changes
        sig { returns(T::Boolean) }
        def actionable?
          improvements.any? || suggested_mutations.any?
        end

        # Get mutations sorted by priority (simple alphabetical for Phase 1)
        sig { returns(MutationsList) }
        def mutation_priority
          suggested_mutations.sort
        end

        # Convert to hash representation
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            trace_id: trace_id,
            diagnosis: diagnosis,
            improvements: improvements,
            confidence: confidence,
            reasoning: reasoning,
            suggested_mutations: suggested_mutations,
            metadata: metadata
          }
        end

        # Generate a concise summary of this reflection
        sig { returns(String) }
        def summary
          confidence_pct = (confidence * 100).round
          mutation_list = suggested_mutations.map(&:to_s).join(', ')
          
          "#{diagnosis.split('.').first}. " \
          "Confidence: #{confidence_pct}%. " \
          "#{improvements.size} improvements suggested. " \
          "Mutations: #{mutation_list}."
        end

        # Check if reflection model was used
        sig { returns(T.nilable(String)) }
        def reflection_model
          metadata[:reflection_model]
        end

        # Get token usage from reflection analysis
        sig { returns(Integer) }
        def token_usage
          metadata[:token_usage] || 0
        end

        # Get analysis duration in milliseconds
        sig { returns(Integer) }
        def analysis_duration_ms
          metadata[:analysis_duration_ms] || 0
        end
      end

      # TraceCollector aggregates execution traces from DSPy events
      # Uses SubscriberMixin for class-level event subscriptions
      class TraceCollector
        include DSPy::Events::SubscriberMixin
        extend T::Sig

        sig { void }
        def initialize
          @traces = T.let([], T::Array[ExecutionTrace])
          @traces_mutex = T.let(Mutex.new, Mutex)
          setup_subscriptions
        end

        sig { returns(T::Array[ExecutionTrace]) }
        attr_reader :traces

        # Get count of collected traces
        sig { returns(Integer) }
        def collected_count
          @traces_mutex.synchronize { @traces.size }
        end

        # Collect trace from event data
        sig { params(event_name: String, event_data: T::Hash[T.any(String, Symbol), T.untyped]).void }
        def collect_trace(event_name, event_data)
          @traces_mutex.synchronize do
            trace_id = event_data['trace_id'] || event_data[:trace_id] || generate_trace_id
            
            # Avoid duplicates
            return if @traces.any? { |t| t.trace_id == trace_id }

            timestamp = event_data['timestamp'] || event_data[:timestamp] || Time.now
            span_id = event_data['span_id'] || event_data[:span_id]
            attributes = event_data['attributes'] || event_data[:attributes] || {}
            metadata = event_data['metadata'] || event_data[:metadata] || {}

            trace = ExecutionTrace.new(
              trace_id: trace_id,
              event_name: event_name,
              timestamp: timestamp,
              span_id: span_id,
              attributes: attributes,
              metadata: metadata
            )

            @traces << trace
          end
        end

        # Get traces for a specific optimization run
        sig { params(run_id: String).returns(T::Array[ExecutionTrace]) }
        def traces_for_run(run_id)
          @traces_mutex.synchronize do
            @traces.select do |trace|
              metadata = trace.metadata
              metadata && metadata[:optimization_run_id] == run_id
            end
          end
        end

        # Get only LLM traces
        sig { returns(T::Array[ExecutionTrace]) }
        def llm_traces
          @traces_mutex.synchronize { @traces.select(&:llm_trace?) }
        end

        # Get only module traces
        sig { returns(T::Array[ExecutionTrace]) }
        def module_traces
          @traces_mutex.synchronize { @traces.select(&:module_trace?) }
        end

        # Clear all collected traces
        sig { void }
        def clear
          @traces_mutex.synchronize { @traces.clear }
        end

        private

        # Set up event subscriptions using SubscriberMixin
        sig { void }
        def setup_subscriptions
          # Subscribe to LLM events
          self.class.add_subscription('llm.*') do |name, attrs|
            collect_trace(name, attrs)
          end

          # Subscribe to module events  
          self.class.add_subscription('*.reasoning_complete') do |name, attrs|
            collect_trace(name, attrs)
          end

          self.class.add_subscription('*.predict_complete') do |name, attrs|
            collect_trace(name, attrs)
          end
        end

        # Generate unique trace ID
        sig { returns(String) }
        def generate_trace_id
          "gepa-trace-#{SecureRandom.hex(4)}"
        end
      end

      # ReflectionEngine performs natural language reflection on execution traces
      # This is the core component that analyzes traces and generates improvement insights
      class ReflectionEngine
        extend T::Sig

        sig { returns(GEPAConfig) }
        attr_reader :config

        sig { params(config: T.nilable(GEPAConfig)).void }
        def initialize(config = nil)
          @config = config || GEPAConfig.new
        end

        # Perform reflective analysis on execution traces
        sig { params(traces: T::Array[ExecutionTrace]).returns(ReflectionResult) }
        def reflect_on_traces(traces)
          reflection_id = generate_reflection_id

          if traces.empty?
            return ReflectionResult.new(
              trace_id: reflection_id,
              diagnosis: 'No traces available for analysis',
              improvements: [],
              confidence: 0.0,
              reasoning: 'Cannot provide reflection without execution traces',
              suggested_mutations: [],
              metadata: {
                reflection_model: @config.reflection_lm,
                analysis_timestamp: Time.now,
                trace_count: 0
              }
            )
          end

          patterns = analyze_execution_patterns(traces)
          improvements = generate_improvement_suggestions(patterns)
          mutations = suggest_mutations(patterns)
          
          # For Phase 1, we generate a simple rule-based analysis
          # Future phases will use LLM-based reflection
          diagnosis = generate_diagnosis(patterns)
          reasoning = generate_reasoning(patterns, traces)
          confidence = calculate_confidence(patterns)

          ReflectionResult.new(
            trace_id: reflection_id,
            diagnosis: diagnosis,
            improvements: improvements,
            confidence: confidence,
            reasoning: reasoning,
            suggested_mutations: mutations,
            metadata: {
              reflection_model: @config.reflection_lm,
              analysis_timestamp: Time.now,
              trace_count: traces.size,
              token_usage: 0 # Phase 1 doesn't use actual LLM reflection
            }
          )
        end

        # Analyze patterns in execution traces
        sig { params(traces: T::Array[ExecutionTrace]).returns(T::Hash[Symbol, T.untyped]) }
        def analyze_execution_patterns(traces)
          llm_traces = traces.select(&:llm_trace?)
          module_traces = traces.select(&:module_trace?)

          total_tokens = llm_traces.sum(&:token_usage)
          unique_models = llm_traces.map(&:model_name).compact.uniq

          {
            llm_traces_count: llm_traces.size,
            module_traces_count: module_traces.size,
            total_tokens: total_tokens,
            unique_models: unique_models,
            avg_response_length: calculate_avg_response_length(llm_traces),
            trace_timespan: calculate_timespan(traces)
          }
        end

        # Generate improvement suggestions based on patterns
        sig { params(patterns: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
        def generate_improvement_suggestions(patterns)
          suggestions = []

          if patterns[:total_tokens] > 500
            suggestions << 'Consider reducing prompt length to lower token usage'
          end

          if patterns[:avg_response_length] < 10
            suggestions << 'Responses seem brief - consider asking for more detailed explanations'
          end

          if patterns[:llm_traces_count] > patterns[:module_traces_count] * 3
            suggestions << 'High LLM usage detected - consider optimizing reasoning chains'
          end

          if patterns[:unique_models].size > 1
            suggestions << 'Multiple models used - consider standardizing on one model for consistency'
          end

          suggestions << 'Add step-by-step reasoning instructions' if suggestions.empty?
          suggestions
        end

        # Suggest mutation operations based on patterns
        sig { params(patterns: T::Hash[Symbol, T.untyped]).returns(T::Array[Symbol]) }
        def suggest_mutations(patterns)
          mutations = []

          avg_length = patterns[:avg_response_length] || 0
          total_tokens = patterns[:total_tokens] || 0
          llm_count = patterns[:llm_traces_count] || 0

          mutations << :expand if avg_length < 15
          mutations << :simplify if total_tokens > 300
          mutations << :combine if llm_count > 2
          mutations << :rewrite if llm_count == 1
          mutations << :rephrase if mutations.empty?
          
          mutations.uniq
        end

        private

        # Generate unique reflection ID
        sig { returns(String) }
        def generate_reflection_id
          "reflection-#{SecureRandom.hex(4)}"
        end

        # Generate diagnosis text
        sig { params(patterns: T::Hash[Symbol, T.untyped]).returns(String) }
        def generate_diagnosis(patterns)
          if patterns[:total_tokens] > 400
            'High token usage indicates potential inefficiency in prompt design'
          elsif patterns[:llm_traces_count] == 0
            'No LLM interactions found - execution may not be working as expected'
          elsif patterns[:avg_response_length] < 10
            'Responses are unusually brief which may indicate prompt clarity issues'
          else
            'Execution patterns appear normal with room for optimization'
          end
        end

        # Generate reasoning text
        sig { params(patterns: T::Hash[Symbol, T.untyped], traces: T::Array[ExecutionTrace]).returns(String) }
        def generate_reasoning(patterns, traces)
          reasoning_parts = []
          
          reasoning_parts << "Analyzed #{traces.size} execution traces"
          reasoning_parts << "#{patterns[:llm_traces_count]} LLM interactions"
          reasoning_parts << "#{patterns[:module_traces_count]} module operations"
          reasoning_parts << "Total token usage: #{patterns[:total_tokens]}"
          
          reasoning_parts.join('. ') + '.'
        end

        # Calculate confidence based on patterns
        sig { params(patterns: T::Hash[Symbol, T.untyped]).returns(Float) }
        def calculate_confidence(patterns)
          base_confidence = 0.7
          
          # More traces = higher confidence
          trace_bonus = [patterns[:llm_traces_count] + patterns[:module_traces_count], 10].min * 0.02
          
          # Reasonable token usage = higher confidence
          token_penalty = patterns[:total_tokens] > 1000 ? -0.1 : 0.0
          
          [(base_confidence + trace_bonus + token_penalty), 1.0].min
        end

        # Calculate average response length from LLM traces
        sig { params(llm_traces: T::Array[ExecutionTrace]).returns(Integer) }
        def calculate_avg_response_length(llm_traces)
          return 0 if llm_traces.empty?
          
          total_length = llm_traces.sum do |trace|
            response = trace.response_text
            response ? response.length : 0
          end
          
          total_length / llm_traces.size
        end

        # Calculate timespan of traces
        sig { params(traces: T::Array[ExecutionTrace]).returns(Float) }
        def calculate_timespan(traces)
          return 0.0 if traces.size < 2
          
          timestamps = traces.map(&:timestamp).sort
          (timestamps.last - timestamps.first).to_f
        end
      end

      # GeneticEngine orchestrates the genetic algorithm for prompt evolution
      # Manages population, selection, and evolution across generations
      class GeneticEngine
        extend T::Sig

        sig { returns(GEPAConfig) }
        attr_reader :config

        sig { returns(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)) }
        attr_reader :metric

        sig { returns(T::Array[T.untyped]) }
        attr_reader :population

        sig { returns(Integer) }
        attr_reader :generation

        sig { params(config: GEPAConfig, metric: T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)).void }
        def initialize(config:, metric:)
          @config = config
          @metric = metric
          @population = T.let([], T::Array[T.untyped])
          @generation = 0
          @fitness_scores = T.let([], T::Array[Float])
        end

        # Initialize population with diverse instruction variants
        sig { params(program: T.untyped).void }
        def initialize_population(program)
          @population = []
          
          # Start with original program
          @population << program
          
          # Generate instruction variants to fill population
          original_instruction = program.signature_class.description
          variants = generate_instruction_variants(original_instruction)
          
          # Create program copies with different instructions
          variants.take(@config.population_size - 1).each do |variant|
            variant_program = create_program_with_instruction(program, variant)
            @population << variant_program
          end
          
          # If we need more candidates, duplicate and mutate
          while @population.size < @config.population_size
            base_program = @population.sample
            mutated = create_program_with_instruction(base_program, 
              generate_instruction_variants(base_program.signature_class.description).first)
            @population << mutated
          end
          
          @generation = 0
        end

        # Evaluate all population members on the training set
        sig { params(trainset: T::Array[T.untyped]).returns(T::Array[Float]) }
        def evaluate_population(trainset)
          @fitness_scores = @population.map do |candidate|
            scores = trainset.map do |example|
              prediction = candidate.call(**example.input_values)
              @metric.call(example, prediction).to_f
            rescue => e
              # Handle evaluation errors gracefully
              0.0
            end
            
            scores.sum / scores.size
          end
          
          @fitness_scores
        end

        # Evolve to next generation using selection and mutation
        sig { params(trainset: T::Array[T.untyped]).void }
        def evolve_generation(trainset)
          current_scores = evaluate_population(trainset)
          
          # Simple selection: keep top 50% and mutate them
          sorted_indices = (0...@population.size).sort_by { |i| -current_scores[i] }
          survivors = sorted_indices.take(@config.population_size / 2)
          
          new_population = []
          
          # Keep best performers
          survivors.each { |i| new_population << @population[i] }
          
          # Fill rest with mutations of survivors
          while new_population.size < @config.population_size
            parent_index = survivors.sample
            parent = @population[parent_index]
            
            # Generate mutation
            variants = generate_instruction_variants(parent.signature_class.description)
            mutated = create_program_with_instruction(parent, variants.first || parent.signature_class.description)
            new_population << mutated
          end
          
          @population = new_population
          @generation += 1
        end

        # Run complete evolution process
        sig { params(program: T.untyped, trainset: T::Array[T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def run_evolution(program, trainset)
          initialize_population(program)
          
          history = []
          
          # Initial evaluation
          initial_scores = evaluate_population(trainset)
          history << {
            generation: 0,
            best_fitness: initial_scores.max,
            avg_fitness: initial_scores.sum / initial_scores.size,
            diversity: population_diversity
          }
          
          # Evolution loop
          @config.num_generations.times do
            evolve_generation(trainset)
            scores = evaluate_population(trainset)
            
            history << {
              generation: @generation,
              best_fitness: scores.max,
              avg_fitness: scores.sum / scores.size,
              diversity: population_diversity
            }
          end
          
          {
            best_candidate: get_best_candidate,
            best_fitness: @fitness_scores.max,
            generation_history: history,
            final_population: @population.dup
          }
        end

        # Get the best performing candidate from current population
        sig { returns(T.untyped) }
        def get_best_candidate
          return @population.first if @fitness_scores.empty?
          
          best_index = @fitness_scores.each_with_index.max_by { |score, _| score }[1]
          @population[best_index]
        end

        # Measure diversity of instructions in current population
        sig { returns(Float) }
        def population_diversity
          return 0.0 if @population.empty?
          
          instructions = @population.map(&:signature_class).map(&:description)
          unique_instructions = instructions.uniq.size
          
          unique_instructions.to_f / @population.size.to_f
        end

        private

        # Generate instruction variants (similar to simple optimization)
        sig { params(original_instruction: String).returns(T::Array[String]) }
        def generate_instruction_variants(original_instruction)
          variants = []
          
          # Add "step by step" variant
          unless original_instruction.include?("step")
            variants << "#{original_instruction} Think step by step."
          end
          
          # Add "detailed" variant
          unless original_instruction.include?("detail")
            variants << "#{original_instruction} Provide detailed reasoning."
          end
          
          # Add "careful" variant
          unless original_instruction.include?("careful")
            variants << "Be careful and accurate. #{original_instruction}"
          end
          
          # Add "examples" variant
          unless original_instruction.include?("example")
            variants << "#{original_instruction} Use examples in your response."
          end
          
          # Add "precise" variant
          unless original_instruction.include?("precise")
            variants << "Be precise and specific. #{original_instruction}"
          end
          
          variants.shuffle.take(5) # Return up to 5 variants, shuffled
        end

        # Create program copy with modified instruction (simplified for Phase 2)
        sig { params(original_program: T.untyped, new_instruction: String).returns(T.untyped) }
        def create_program_with_instruction(original_program, new_instruction)
          # For Phase 2, return the original program
          # Future implementation will create actual modified programs
          original_program
        end
      end

      # FitnessScore represents multi-dimensional evaluation results
      class FitnessScore < Data.define(
        :primary_score,
        :secondary_scores,
        :overall_score,
        :metadata
      )
        extend T::Sig

        sig do
          params(
            primary_score: Float,
            secondary_scores: T::Hash[Symbol, Float],
            overall_score: Float,
            metadata: T.nilable(T::Hash[Symbol, T.untyped])
          ).void
        end
        def initialize(primary_score:, secondary_scores:, overall_score:, metadata: {})
          # Validate score ranges
          [primary_score, overall_score].each do |score|
            if score < 0.0 || score > 1.0
              raise ArgumentError, "Score must be between 0.0 and 1.0, got #{score}"
            end
          end

          secondary_scores.each do |name, score|
            if score < 0.0 || score > 1.0
              raise ArgumentError, "Secondary score #{name} must be between 0.0 and 1.0, got #{score}"
            end
          end

          super(
            primary_score: primary_score,
            secondary_scores: secondary_scores.freeze,
            overall_score: overall_score,
            metadata: (metadata || {}).freeze
          )
        end

        # Check if this score is dominated by another (for Pareto analysis)
        sig { params(other: FitnessScore).returns(T::Boolean) }
        def dominated_by?(other)
          return false if overall_score > other.overall_score
          return true if overall_score < other.overall_score

          # If overall scores are equal, check secondary metrics
          secondary_scores.all? do |metric, score|
            other_score = other.secondary_scores[metric] || 0.0
            score <= other_score
          end
        end

        # Get combined score for specific objectives
        sig { params(objectives: T::Array[Symbol]).returns(Float) }
        def score_for_objectives(objectives)
          relevant_scores = objectives.map { |obj| secondary_scores[obj] || 0.0 }
          return primary_score if relevant_scores.empty?

          (primary_score + relevant_scores.sum) / (objectives.size + 1)
        end
      end

      # FitnessEvaluator provides multi-dimensional evaluation of prompt candidates
      class FitnessEvaluator
        extend T::Sig

        sig { returns(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)) }
        attr_reader :primary_metric

        sig { returns(GEPAConfig) }
        attr_reader :config

        sig { returns(T::Hash[Symbol, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)]) }
        attr_reader :secondary_metrics

        sig do
          params(
            primary_metric: T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped),
            config: GEPAConfig,
            secondary_metrics: T.nilable(T::Hash[Symbol, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)])
          ).void
        end
        def initialize(primary_metric:, config:, secondary_metrics: nil)
          @primary_metric = primary_metric
          @config = config
          @secondary_metrics = secondary_metrics || default_secondary_metrics
          @trace_collector = TraceCollector.new
        end

        # Evaluate a single candidate program
        sig { params(program: T.untyped, trainset: T::Array[T.untyped]).returns(FitnessScore) }
        def evaluate_candidate(program, trainset)
          start_time = Time.now
          predictions = []
          traces = []

          # Collect primary metric scores and execution data
          primary_scores = trainset.map do |example|
            prediction_start = Time.now
            prediction = program.call(**example.input_values)
            prediction_time = Time.now - prediction_start

            predictions << {
              prediction: prediction,
              latency: prediction_time,
              example: example
            }

            @primary_metric.call(example, prediction).to_f
          rescue => e
            # Handle prediction errors
            predictions << {
              prediction: nil,
              latency: 0.0,
              example: example,
              error: e.message
            }
            0.0
          end

          primary_score = primary_scores.sum / primary_scores.size

          # Calculate secondary metrics
          secondary_scores = {}
          
          # Token efficiency (mock data for now - will be replaced with real trace collection)
          mock_traces = predictions.map.with_index do |pred, i|
            OpenStruct.new(token_usage: 50 + rand(100))
          end
          secondary_scores[:token_efficiency] = calculate_token_efficiency(mock_traces, predictions.size)

          # Response consistency
          response_texts = predictions.map { |p| p[:prediction]&.answer&.to_s || '' }
          secondary_scores[:consistency] = calculate_consistency(response_texts)

          # Latency performance
          latencies = predictions.map { |p| p[:latency] }
          secondary_scores[:latency] = calculate_latency_score(latencies)

          # Calculate weighted overall score
          overall_score = calculate_overall_score(primary_score, secondary_scores)

          FitnessScore.new(
            primary_score: primary_score,
            secondary_scores: secondary_scores,
            overall_score: overall_score,
            metadata: {
              evaluation_time: Time.now - start_time,
              examples_count: trainset.size,
              errors_count: predictions.count { |p| p[:error] }
            }
          )
        end

        # Evaluate multiple candidates in batch
        sig { params(programs: T::Array[T.untyped], trainset: T::Array[T.untyped]).returns(T::Array[FitnessScore]) }
        def batch_evaluate(programs, trainset)
          programs.map { |program| evaluate_candidate(program, trainset) }
        end

        # Compare two fitness scores (positive if first is better)
        sig { params(score1: FitnessScore, score2: FitnessScore).returns(Float) }
        def compare_candidates(score1, score2)
          score1.overall_score - score2.overall_score
        end

        # Rank candidates by fitness (returns indices sorted by fitness, best first)
        sig { params(scores: T::Array[FitnessScore]).returns(T::Array[Integer]) }
        def rank_candidates(scores)
          scores.each_with_index.sort_by { |score, _| -score.overall_score }.map(&:last)
        end

        private

        # Default secondary metrics for fitness evaluation
        sig { returns(T::Hash[Symbol, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)]) }
        def default_secondary_metrics
          {
            token_efficiency: proc { |traces, count| calculate_token_efficiency(traces, count) },
            consistency: proc { |responses| calculate_consistency(responses) },
            latency: proc { |latencies| calculate_latency_score(latencies) }
          }
        end

        # Calculate token usage efficiency (lower usage = higher score)
        sig { params(traces: T::Array[T.untyped], example_count: Integer).returns(Float) }
        def calculate_token_efficiency(traces, example_count)
          return 1.0 if traces.empty? || example_count == 0

          total_tokens = traces.sum(&:token_usage)
          avg_tokens_per_example = total_tokens.to_f / example_count

          # Efficiency decreases as token usage increases
          # Assume 100 tokens per example is baseline (score 0.5)
          baseline_tokens = 100.0
          efficiency = baseline_tokens / (baseline_tokens + avg_tokens_per_example)

          [efficiency, 1.0].min
        end

        # Calculate consistency of responses (similar structure = higher score)
        sig { params(responses: T::Array[String]).returns(Float) }
        def calculate_consistency(responses)
          return 1.0 if responses.empty? || responses.size == 1

          # Simple consistency measure: average word overlap between responses
          word_sets = responses.map { |response| response.downcase.split.to_set }
          
          total_similarity = 0.0
          comparisons = 0

          word_sets.each_with_index do |set1, i|
            word_sets[(i+1)..-1].each do |set2|
              intersection = set1 & set2
              union = set1 | set2
              
              similarity = union.empty? ? 0.0 : intersection.size.to_f / union.size
              total_similarity += similarity
              comparisons += 1
            end
          end

          comparisons == 0 ? 1.0 : total_similarity / comparisons
        end

        # Calculate latency performance score (faster = higher score)
        sig { params(latencies: T::Array[Float]).returns(Float) }
        def calculate_latency_score(latencies)
          return 1.0 if latencies.empty?

          avg_latency = latencies.sum / latencies.size
          
          # Penalize high latencies (assume 2 seconds is baseline for 0.5 score)
          baseline_latency = 2.0
          latency_score = baseline_latency / (baseline_latency + avg_latency)

          [latency_score, 1.0].min
        end

        # Calculate weighted overall score combining primary and secondary metrics
        sig { params(primary_score: Float, secondary_scores: T::Hash[Symbol, Float]).returns(Float) }
        def calculate_overall_score(primary_score, secondary_scores)
          # Weight primary metric at 70%, secondary metrics at 30%
          primary_weight = 0.7
          secondary_weight = 0.3

          return primary_score if secondary_scores.empty?

          avg_secondary = secondary_scores.values.sum / secondary_scores.size
          overall = (primary_score * primary_weight) + (avg_secondary * secondary_weight)

          [overall, 1.0].min
        end
      end

      # MutationEngine: Handles LLM-based prompt transformations for genetic evolution
      class MutationEngine
        extend T::Sig

        sig { returns(GEPAConfig) }
        attr_reader :config

        sig { params(config: GEPAConfig).void }
        def initialize(config:)
          @config = config
        end

        # Mutate a single program with LLM-based transformations
        sig { params(program: T.untyped).returns(T.untyped) }
        def mutate_program(program)
          return program if rand > @config.mutation_rate

          begin
            original_instruction = extract_instruction(program)
            mutation_type = select_mutation_type(original_instruction)
            mutated_instruction = apply_mutation(original_instruction, mutation_type)
            
            create_mutated_program(program, mutated_instruction)
          rescue => e
            # Return original program on mutation failure
            program
          end
        end

        # Batch mutation of multiple programs
        sig { params(programs: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def batch_mutate(programs)
          return [] if programs.empty?
          
          programs.map { |program| mutate_program(program) }
        end

        private

        # Extract instruction text from program
        sig { params(program: T.untyped).returns(String) }
        def extract_instruction(program)
          if program.signature_class&.description
            program.signature_class.description
          else
            "Analyze the input and complete the task accurately"
          end
        end

        # Apply specific mutation type to instruction
        sig { params(instruction: String, mutation_type: Symbol).returns(String) }
        def apply_mutation(instruction, mutation_type)
          case mutation_type
          when :rewrite
            apply_rewrite_mutation(instruction)
          when :expand
            apply_expand_mutation(instruction)
          when :simplify
            apply_simplify_mutation(instruction)
          when :combine
            apply_combine_mutation(instruction)
          when :rephrase
            apply_rephrase_mutation(instruction)
          else
            instruction
          end
        end

        # Rewrite the instruction with different phrasing
        sig { params(instruction: String).returns(String) }
        def apply_rewrite_mutation(instruction)
          # Simple rewrite patterns for now - in full implementation would use LLM
          patterns = [
            -> (inst) { "Carefully #{inst.downcase}" },
            -> (inst) { "Please #{inst.downcase}" },
            -> (inst) { "#{inst} with precision" }
          ]
          
          patterns.sample.call(instruction)
        end

        # Expand instruction with additional context
        sig { params(instruction: String).returns(String) }
        def apply_expand_mutation(instruction)
          expansions = [
            "Think step by step.",
            "Provide detailed reasoning.",
            "Consider all aspects carefully.",
            "Explain your thought process."
          ]
          
          "#{instruction} #{expansions.sample}"
        end

        # Simplify instruction by removing complex terms
        sig { params(instruction: String).returns(String) }
        def apply_simplify_mutation(instruction)
          # Remove common complexity words
          simplified = instruction.gsub(/\b(carefully|detailed|comprehensive|thorough)\b/i, '')
                                  .gsub(/\s+/, ' ')
                                  .strip
          
          simplified.empty? ? instruction : simplified
        end

        # Combine instruction with complementary strategies
        sig { params(instruction: String).returns(String) }
        def apply_combine_mutation(instruction)
          strategies = [
            "Break down the problem systematically.",
            "Use logical reasoning.",
            "Apply domain knowledge.",
            "Consider edge cases."
          ]
          
          "#{instruction} #{strategies.sample}"
        end

        # Rephrase instruction with synonyms
        sig { params(instruction: String).returns(String) }  
        def apply_rephrase_mutation(instruction)
          # Simple synonym replacement - in full implementation would use LLM
          synonyms = {
            'solve' => 'resolve',
            'answer' => 'respond to',
            'analyze' => 'examine',
            'calculate' => 'compute',
            'determine' => 'identify'
          }
          
          result = instruction.dup
          synonyms.each do |original, replacement|
            result.gsub!(/\b#{original}\b/i, replacement) if rand < 0.3
          end
          
          result
        end

        # Create new program with mutated instruction
        sig { params(original_program: T.untyped, new_instruction: String).returns(T.untyped) }
        def create_mutated_program(original_program, new_instruction)
          # For now, return the original program as we don't modify instruction in place
          # In full implementation, would create new program instance with modified instruction
          original_program
        end

        # Select mutation type based on context and configuration
        sig { params(instruction: T.nilable(String)).returns(Symbol) }
        def select_mutation_type(instruction = nil)
          # Adaptive selection based on instruction characteristics
          if instruction && instruction.length < 20
            # Short instructions benefit from expansion
            [:expand, :combine].sample
          elsif instruction && instruction.length > 100
            # Long instructions benefit from simplification
            [:simplify, :rephrase].sample
          else
            # Balanced selection from all types
            @config.mutation_types.sample
          end
        end

        # Calculate diversity of mutations applied
        sig { params(mutations: T::Array[Symbol]).returns(Float) }
        def mutation_diversity(mutations)
          return 0.0 if mutations.empty?
          
          unique_types = mutations.uniq.size
          total_types = @config.mutation_types.size
          
          unique_types.to_f / total_types
        end
      end

      # Configuration for GEPA optimization
      class GEPAConfig < Config
        extend T::Sig

        sig { returns(String) }
        attr_accessor :reflection_lm

        sig { returns(Integer) }
        attr_accessor :num_generations

        sig { returns(Integer) }
        attr_accessor :population_size

        sig { returns(Float) }
        attr_accessor :mutation_rate

        sig { returns(T::Boolean) }
        attr_accessor :use_pareto_selection

        sig { returns(T::Boolean) }
        attr_accessor :simple_mode
        sig { returns(T::Array[Symbol]) }
        attr_accessor :mutation_types

        sig { void }
        def initialize
          super
          @reflection_lm = 'gpt-4o'
          @num_generations = 10
          @population_size = 8
          @mutation_rate = 0.7
          @use_pareto_selection = true
          @simple_mode = false
          @mutation_types = [:rewrite, :expand, :simplify, :combine, :rephrase]
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          super.merge({
            reflection_lm: @reflection_lm,
            num_generations: @num_generations,
            population_size: @population_size,
            mutation_rate: @mutation_rate,
            use_pareto_selection: @use_pareto_selection,
            simple_mode: @simple_mode,
            mutation_types: @mutation_types
          })
        end
      end

      sig { returns(GEPAConfig) }
      attr_reader :config

      sig do
        params(
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
          config: T.nilable(GEPAConfig)
        ).void
      end
      def initialize(metric: nil, config: nil)
        @config = config || GEPAConfig.new
        super(metric: metric, config: @config)
      end

      # Main optimization method
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).returns(OptimizationResult)
      end
      def compile(program, trainset:, valset: nil)
        validate_inputs(program, trainset, valset)

        instrument_step('gepa_compile', {
          trainset_size: trainset.size,
          valset_size: valset&.size || 0,
          num_generations: @config.num_generations,
          population_size: @config.population_size
        }) do
          # Simple optimization for Phase 1.5 - basic instruction optimization
          if @config.simple_mode
            perform_simple_optimization(program, trainset, valset)
          else
            # Return basic result for Phase 1
            OptimizationResult.new(
              optimized_program: program,
              scores: { gepa_score: 0.0 },
              history: { 
                num_generations: @config.num_generations,
                population_size: @config.population_size,
                phase: 'Phase 1 - Basic Structure'
              },
              best_score_name: 'gepa_score',
              best_score_value: 0.0,
              metadata: {
                optimizer: 'GEPA',
                reflection_lm: @config.reflection_lm,
                implementation_status: 'Phase 1 - Infrastructure Complete'
              }
            )
          end
        end
      end

      private

      # Simple optimization implementation for testing
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).returns(OptimizationResult)
      end
      def perform_simple_optimization(program, trainset, valset)
        return basic_result(program) unless program.respond_to?(:signature_class)
        
        original_description = program.signature_class.description
        best_program = program
        best_score = simple_evaluate_program(program, trainset)
        
        # Try different instruction variations
        instruction_variants = generate_instruction_variants(original_description)
        
        instruction_variants.each_with_index do |variant, index|
          emit_event('instruction_variant_test', {
            variant: variant,
            iteration: index + 1,
            total_variants: instruction_variants.size
          })
          
          # Create modified program
          modified_program = create_program_with_instruction(program, variant)
          score = simple_evaluate_program(modified_program, trainset)
          
          if score > best_score
            best_program = modified_program
            best_score = score
            
            emit_event('improvement_found', {
              new_score: score,
              previous_score: best_score,
              instruction: variant
            })
          end
        end
        
        OptimizationResult.new(
          optimized_program: best_program,
          scores: { accuracy: best_score },
          history: {
            original_score: simple_evaluate_program(program, trainset),
            variants_tested: instruction_variants.size,
            best_instruction: best_program.signature_class.description
          },
          best_score_name: 'accuracy',
          best_score_value: best_score,
          metadata: {
            optimizer: 'GEPA',
            mode: 'Simple Optimization',
            reflection_lm: @config.reflection_lm
          }
        )
      end

      # Generate variations of the instruction
      sig { params(original_instruction: String).returns(T::Array[String]) }
      def generate_instruction_variants(original_instruction)
        variants = []
        
        # Add "step by step" variant
        unless original_instruction.include?("step")
          variants << "#{original_instruction} Think step by step."
        end
        
        # Add "detailed" variant  
        unless original_instruction.include?("detail")
          variants << "#{original_instruction} Provide detailed reasoning."
        end
        
        # Add "careful" variant
        unless original_instruction.include?("careful")
          variants << "Be careful and accurate. #{original_instruction}"
        end
        
        variants.take(3) # Limit to 3 variants for simple mode
      end

      # Create a new program instance with modified instruction
      sig { params(original_program: T.untyped, new_instruction: String).returns(T.untyped) }
      def create_program_with_instruction(original_program, new_instruction)
        # This is a simplified approach - in real implementation we'd need
        # more sophisticated program modification
        original_program
      end

      # Simple evaluation for testing (different from base class evaluate_program)
      sig { params(program: T.untyped, trainset: T::Array[T.untyped]).returns(Float) }
      def simple_evaluate_program(program, trainset)
        return 0.0 unless @metric
        
        scores = trainset.map do |example|
          prediction = program.call(**example.input_values)
          @metric.call(example, prediction).to_f
        rescue => e
          emit_event('evaluation_error', { error: e.message, example: example })
          0.0
        end
        
        scores.sum / scores.size
      end

      # Return basic result when simple optimization isn't applicable
      sig { params(program: T.untyped).returns(OptimizationResult) }
      def basic_result(program)
        OptimizationResult.new(
          optimized_program: program,
          scores: { gepa_score: 0.0 },
          history: { phase: 'Phase 1 - Basic Structure' },
          best_score_name: 'gepa_score',
          best_score_value: 0.0,
          metadata: {
            optimizer: 'GEPA',
            implementation_status: 'Phase 1 - Infrastructure Complete'
          }
        )
      end
    end
  end
end