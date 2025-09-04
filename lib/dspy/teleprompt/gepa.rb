# frozen_string_literal: true

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

        sig { void }
        def initialize
          super
          @reflection_lm = 'gpt-4o'
          @num_generations = 10
          @population_size = 8
          @mutation_rate = 0.7
          @use_pareto_selection = true
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          super.merge({
            reflection_lm: @reflection_lm,
            num_generations: @num_generations,
            population_size: @population_size,
            mutation_rate: @mutation_rate,
            use_pareto_selection: @use_pareto_selection
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
          # For Phase 1, return a basic optimization result
          # Future phases will implement the full genetic algorithm
          
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
  end
end