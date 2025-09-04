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

      # Enum for mutation operation types
      class MutationType < T::Enum
        enums do
          Rewrite = new
          Expand = new
          Simplify = new
          Combine = new
          Rephrase = new
        end
      end

      # Enum for crossover operation types  
      class CrossoverType < T::Enum
        enums do
          Uniform = new
          Blend = new
          Structured = new
        end
      end

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
        
        # LLM-based reflection methods for Phase 2
        
        public
        
        # Perform LLM-based reflection on execution traces
        sig { params(traces: T::Array[ExecutionTrace]).returns(ReflectionResult) }
        def reflect_with_llm(traces)
          return reflect_on_traces(traces) if traces.empty?
          
          begin
            prompt = generate_reflection_prompt(traces)
            reflection_response = call_reflection_llm(prompt)
            parse_llm_reflection(reflection_response, traces)
          rescue => e
            # Fallback to rule-based analysis on LLM failure
            fallback_result = reflect_on_traces(traces)
            fallback_result.class.new(
              trace_id: fallback_result.trace_id,
              diagnosis: "LLM reflection failed (#{e.message}), using fallback analysis: #{fallback_result.diagnosis}",
              improvements: fallback_result.improvements,
              confidence: [fallback_result.confidence * 0.5, 0.5].min,
              reasoning: "Fallback to rule-based analysis after LLM error: #{fallback_result.reasoning}",
              suggested_mutations: fallback_result.suggested_mutations,
              metadata: fallback_result.metadata.merge(
                llm_error: e.message,
                fallback_used: true
              )
            )
          end
        end
        
        # Generate structured reflection prompt for LLM (public API)
        sig { params(traces: T::Array[ExecutionTrace]).returns(String) }
        def generate_reflection_prompt(traces)
          if traces.empty?
            return <<~PROMPT
              You are analyzing execution traces for a genetic algorithm-based prompt optimization system called GEPA.
              
              **Task**: Analyze execution patterns and provide optimization recommendations.
              
              **Context**: No execution traces available.
              
              Please provide your analysis in the following JSON format:
              {
                "diagnosis": "Brief description of what you observed",
                "improvements": ["List of actionable improvement suggestions"],
                "confidence": 0.0,
                "reasoning": "Your reasoning process",
                "suggested_mutations": ["expand", "rewrite", "simplify", "combine", "rephrase"],
                "insights": {
                  "pattern_detected": "no_data",
                  "optimization_opportunity": "data_collection"
                }
              }
            PROMPT
          end
          
          summary = trace_summary_for_reflection(traces)
          insights = extract_optimization_insights(traces)
          
          <<~PROMPT
            You are analyzing execution traces for a genetic algorithm-based prompt optimization system called GEPA.
            
            **Task**: Analyze execution patterns and provide optimization recommendations for prompt evolution.
            
            **Execution Summary**:
            #{summary}
            
            **Optimization Context**:
            - This is part of a genetic algorithm for prompt optimization
            - Available mutation types: rewrite, expand, simplify, combine, rephrase
            - Goal is to improve prompt effectiveness through iterative evolution
            - Focus on actionable insights that can guide mutation and crossover operations
            
            **Key Optimization Insights**:
            #{insights.map { |k, v| "- #{k}: #{v.is_a?(Hash) ? v.values.join(', ') : v}" }.join("\n")}
            
            **Sample Traces**:
            #{format_traces_for_prompt(traces.take(3))}
            
            Please analyze these execution patterns and provide optimization recommendations in the following JSON format:
            {
              "diagnosis": "Brief description of execution patterns and issues identified",
              "improvements": ["List of 2-4 specific, actionable improvement suggestions"],
              "confidence": 0.85,
              "reasoning": "Your detailed reasoning process for the analysis",
              "suggested_mutations": ["List of 2-3 mutation types that would be most beneficial"],
              "insights": {
                "pattern_detected": "primary_pattern_identified", 
                "optimization_opportunity": "key_area_for_improvement"
              }
            }
            
            Focus on practical recommendations that will improve prompt performance through genetic algorithm evolution.
          PROMPT
        end
        
        # Parse LLM reflection response into ReflectionResult (public API)
        sig { params(response_text: String, original_traces: T::Array[ExecutionTrace]).returns(ReflectionResult) }
        def parse_llm_reflection(response_text, original_traces)
          reflection_id = generate_reflection_id
          
          begin
            parsed = JSON.parse(response_text)
            
            # Extract and validate components
            diagnosis = parsed['diagnosis'] || 'LLM reflection analysis'
            improvements = Array(parsed['improvements']).select { |i| i.is_a?(String) && !i.strip.empty? }
            confidence = [parsed['confidence'].to_f, 1.0].min
            reasoning = parsed['reasoning'] || 'LLM-based analysis of execution traces'
            
            # Validate and sanitize mutation suggestions
            raw_mutations = Array(parsed['suggested_mutations'])
            valid_mutations = raw_mutations.filter_map do |mut|
              mutation_symbol = mut.to_s.downcase.to_sym
              if [:rewrite, :expand, :simplify, :combine, :rephrase].include?(mutation_symbol)
                mutation_symbol
              end
            end.uniq
            
            # Ensure we have at least one valid mutation suggestion
            valid_mutations = [:rewrite] if valid_mutations.empty?
            
            ReflectionResult.new(
              trace_id: reflection_id,
              diagnosis: diagnosis,
              improvements: improvements,
              confidence: confidence,
              reasoning: reasoning,
              suggested_mutations: valid_mutations,
              metadata: {
                reflection_model: @config.reflection_lm,
                analysis_timestamp: Time.now,
                trace_count: original_traces.size,
                token_usage: estimate_token_usage(response_text),
                llm_based: true,
                insights: parsed['insights'] || {}
              }
            )
            
          rescue JSON::ParserError => e
            # Handle malformed JSON response
            ReflectionResult.new(
              trace_id: reflection_id,
              diagnosis: "LLM reflection JSON parsing error: #{e.message}",
              improvements: ['Review prompt structure and LLM response format'],
              confidence: 0.3,
              reasoning: "Failed to parse LLM reflection response as valid JSON",
              suggested_mutations: [:rewrite],
              metadata: {
                reflection_model: @config.reflection_lm,
                analysis_timestamp: Time.now,
                trace_count: original_traces.size,
                token_usage: 0,
                parsing_error: e.message,
                raw_response: response_text.length > 500 ? "#{response_text[0..500]}..." : response_text
              }
            )
          end
        end
        
        # Create comprehensive trace summary for reflection (public API)
        sig { params(traces: T::Array[ExecutionTrace]).returns(String) }
        def trace_summary_for_reflection(traces)
          return "No execution traces available" if traces.empty?
          
          llm_traces = traces.select(&:llm_trace?)
          module_traces = traces.select(&:module_trace?)
          
          total_tokens = llm_traces.sum(&:token_usage)
          unique_models = llm_traces.map(&:model_name).compact.uniq
          timespan = calculate_timespan(traces)
          
          avg_response_length = if llm_traces.any?
            total_length = llm_traces.sum { |t| t.response_text&.length || 0 }
            total_length / llm_traces.size
          else
            0
          end
          
          <<~SUMMARY
            Total traces: #{traces.size}
            LLM interactions: #{llm_traces.size}
            Module calls: #{module_traces.size}
            Total tokens: #{total_tokens}
            Models used: #{unique_models.join(', ')}
            Average response length: #{avg_response_length} characters
            Execution timespan: #{timespan.round(2)} seconds
          SUMMARY
        end
        
        # Extract optimization insights from trace analysis (public API)
        sig { params(traces: T::Array[ExecutionTrace]).returns(T::Hash[Symbol, T.untyped]) }
        def extract_optimization_insights(traces)
          llm_traces = traces.select(&:llm_trace?)
          
          insights = {
            token_efficiency: analyze_token_efficiency(llm_traces),
            response_quality: analyze_response_quality(llm_traces),
            model_consistency: analyze_model_consistency(llm_traces)
          }
          
          insights
        end
        
        # Reflection with optimization context (public API)
        sig { params(traces: T::Array[ExecutionTrace], context: T::Hash[Symbol, T.untyped]).returns(ReflectionResult) }
        def reflection_with_context(traces, context)
          base_result = reflect_with_llm(traces)
          
          # Incorporate context into reasoning
          context_reasoning = "Generation #{context[:generation] || 'unknown'} analysis. "
          context_reasoning += "Population size: #{context[:population_size] || 'unknown'}. "
          
          if context[:current_best_score]
            context_reasoning += "Current best score: #{context[:current_best_score]}. "
          end
          
          # Adjust mutation suggestions based on history
          adjusted_mutations = adjust_mutations_for_history(
            base_result.suggested_mutations,
            context[:mutation_history] || [],
            context[:recent_performance_trend]
          )
          
          ReflectionResult.new(
            trace_id: base_result.trace_id,
            diagnosis: base_result.diagnosis,
            improvements: base_result.improvements,
            confidence: base_result.confidence,
            reasoning: context_reasoning + base_result.reasoning,
            suggested_mutations: adjusted_mutations,
            metadata: base_result.metadata.merge(optimization_context: context)
          )
        end
        
        # LLM-based reflection methods for Phase 2
        
        public
        
        # Perform LLM-based reflection on execution traces
        sig { params(traces: T::Array[ExecutionTrace]).returns(ReflectionResult) }
        def reflect_with_llm(traces)
          return reflect_on_traces(traces) if traces.empty?
          
          begin
            prompt = generate_reflection_prompt(traces)
            reflection_response = call_reflection_llm(prompt)
            parse_llm_reflection(reflection_response, traces)
          rescue => e
            # Fallback to rule-based analysis on LLM failure
            fallback_result = reflect_on_traces(traces)
            fallback_result.class.new(
              trace_id: fallback_result.trace_id,
              diagnosis: "LLM reflection failed (#{e.message}), using fallback analysis: #{fallback_result.diagnosis}",
              improvements: fallback_result.improvements,
              confidence: [fallback_result.confidence * 0.5, 0.5].min,
              reasoning: "Fallback to rule-based analysis after LLM error: #{fallback_result.reasoning}",
              suggested_mutations: fallback_result.suggested_mutations,
              metadata: fallback_result.metadata.merge(
                llm_error: e.message,
                fallback_used: true
              )
            )
          end
        end
        
        # Generate structured reflection prompt for LLM (public API)
        sig { params(traces: T::Array[ExecutionTrace]).returns(String) }
        def generate_reflection_prompt(traces)
          if traces.empty?
            return <<~PROMPT
              You are analyzing execution traces for a genetic algorithm-based prompt optimization system called GEPA.
              
              **Task**: Analyze execution patterns and provide optimization recommendations.
              
              **Context**: No execution traces available.
              
              Please provide your analysis in the following JSON format:
              {
                "diagnosis": "Brief description of what you observed",
                "improvements": ["List of actionable improvement suggestions"],
                "confidence": 0.0,
                "reasoning": "Your reasoning process",
                "suggested_mutations": ["expand", "rewrite", "simplify", "combine", "rephrase"],
                "insights": {
                  "pattern_detected": "no_data",
                  "optimization_opportunity": "data_collection"
                }
              }
            PROMPT
          end
          
          summary = trace_summary_for_reflection(traces)
          insights = extract_optimization_insights(traces)
          
          <<~PROMPT
            You are analyzing execution traces for a genetic algorithm-based prompt optimization system called GEPA.
            
            **Task**: Analyze execution patterns and provide optimization recommendations for prompt evolution.
            
            **Execution Summary**:
            #{summary}
            
            **Optimization Context**:
            - This is part of a genetic algorithm for prompt optimization
            - Available mutation types: rewrite, expand, simplify, combine, rephrase
            - Goal is to improve prompt effectiveness through iterative evolution
            - Focus on actionable insights that can guide mutation and crossover operations
            
            **Key Optimization Insights**:
            #{insights.map { |k, v| "- #{k}: #{v.is_a?(Hash) ? v.values.join(', ') : v}" }.join("\n")}
            
            **Sample Traces**:
            #{format_traces_for_prompt(traces.take(3))}
            
            Please analyze these execution patterns and provide optimization recommendations in the following JSON format:
            {
              "diagnosis": "Brief description of execution patterns and issues identified",
              "improvements": ["List of 2-4 specific, actionable improvement suggestions"],
              "confidence": 0.85,
              "reasoning": "Your detailed reasoning process for the analysis",
              "suggested_mutations": ["List of 2-3 mutation types that would be most beneficial"],
              "insights": {
                "pattern_detected": "primary_pattern_identified", 
                "optimization_opportunity": "key_area_for_improvement"
              }
            }
            
            Focus on practical recommendations that will improve prompt performance through genetic algorithm evolution.
          PROMPT
        end
        
        # Parse LLM reflection response into ReflectionResult (public API)
        sig { params(response_text: String, original_traces: T::Array[ExecutionTrace]).returns(ReflectionResult) }
        def parse_llm_reflection(response_text, original_traces)
          reflection_id = generate_reflection_id
          
          begin
            parsed = JSON.parse(response_text)
            
            # Extract and validate components
            diagnosis = parsed['diagnosis'] || 'LLM reflection analysis'
            improvements = Array(parsed['improvements']).select { |i| i.is_a?(String) && !i.strip.empty? }
            confidence = [parsed['confidence'].to_f, 1.0].min
            reasoning = parsed['reasoning'] || 'LLM-based analysis of execution traces'
            
            # Validate and sanitize mutation suggestions
            raw_mutations = Array(parsed['suggested_mutations'])
            valid_mutations = raw_mutations.filter_map do |mut|
              mutation_symbol = mut.to_s.downcase.to_sym
              if [:rewrite, :expand, :simplify, :combine, :rephrase].include?(mutation_symbol)
                mutation_symbol
              end
            end.uniq
            
            # Ensure we have at least one valid mutation suggestion
            valid_mutations = [:rewrite] if valid_mutations.empty?
            
            ReflectionResult.new(
              trace_id: reflection_id,
              diagnosis: diagnosis,
              improvements: improvements,
              confidence: confidence,
              reasoning: reasoning,
              suggested_mutations: valid_mutations,
              metadata: {
                reflection_model: @config.reflection_lm,
                analysis_timestamp: Time.now,
                trace_count: original_traces.size,
                token_usage: estimate_token_usage(response_text),
                llm_based: true,
                insights: parsed['insights'] || {}
              }
            )
            
          rescue JSON::ParserError => e
            # Handle malformed JSON response
            ReflectionResult.new(
              trace_id: reflection_id,
              diagnosis: "LLM reflection JSON parsing error: #{e.message}",
              improvements: ['Review prompt structure and LLM response format'],
              confidence: 0.3,
              reasoning: "Failed to parse LLM reflection response as valid JSON",
              suggested_mutations: [:rewrite],
              metadata: {
                reflection_model: @config.reflection_lm,
                analysis_timestamp: Time.now,
                trace_count: original_traces.size,
                token_usage: 0,
                parsing_error: e.message,
                raw_response: response_text.length > 500 ? "#{response_text[0..500]}..." : response_text
              }
            )
          end
        end
        
        # Create comprehensive trace summary for reflection (public API)
        sig { params(traces: T::Array[ExecutionTrace]).returns(String) }
        def trace_summary_for_reflection(traces)
          return "No execution traces available" if traces.empty?
          
          llm_traces = traces.select(&:llm_trace?)
          module_traces = traces.select(&:module_trace?)
          
          total_tokens = llm_traces.sum(&:token_usage)
          unique_models = llm_traces.map(&:model_name).compact.uniq
          timespan = calculate_timespan(traces)
          
          avg_response_length = if llm_traces.any?
            total_length = llm_traces.sum { |t| t.response_text&.length || 0 }
            total_length / llm_traces.size
          else
            0
          end
          
          <<~SUMMARY
            Total traces: #{traces.size}
            LLM interactions: #{llm_traces.size}
            Module calls: #{module_traces.size}
            Total tokens: #{total_tokens}
            Models used: #{unique_models.join(', ')}
            Average response length: #{avg_response_length} characters
            Execution timespan: #{timespan.round(2)} seconds
          SUMMARY
        end
        
        # Extract optimization insights from trace analysis (public API)
        sig { params(traces: T::Array[ExecutionTrace]).returns(T::Hash[Symbol, T.untyped]) }
        def extract_optimization_insights(traces)
          llm_traces = traces.select(&:llm_trace?)
          
          insights = {
            token_efficiency: analyze_token_efficiency(llm_traces),
            response_quality: analyze_response_quality(llm_traces),
            model_consistency: analyze_model_consistency(llm_traces)
          }
          
          insights
        end
        
        # Reflection with optimization context (public API)
        sig { params(traces: T::Array[ExecutionTrace], context: T::Hash[Symbol, T.untyped]).returns(ReflectionResult) }
        def reflection_with_context(traces, context)
          base_result = reflect_with_llm(traces)
          
          # Incorporate context into reasoning
          context_reasoning = "Generation #{context[:generation] || 'unknown'} analysis. "
          context_reasoning += "Population size: #{context[:population_size] || 'unknown'}. "
          
          if context[:current_best_score]
            context_reasoning += "Current best score: #{context[:current_best_score]}. "
          end
          
          # Adjust mutation suggestions based on history
          adjusted_mutations = adjust_mutations_for_history(
            base_result.suggested_mutations,
            context[:mutation_history] || [],
            context[:recent_performance_trend]
          )
          
          ReflectionResult.new(
            trace_id: base_result.trace_id,
            diagnosis: base_result.diagnosis,
            improvements: base_result.improvements,
            confidence: base_result.confidence,
            reasoning: context_reasoning + base_result.reasoning,
            suggested_mutations: adjusted_mutations,
            metadata: base_result.metadata.merge(optimization_context: context)
          )
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
        
        # Call LLM for reflection analysis
        sig { params(prompt: String).returns(String) }
        def call_reflection_llm(prompt)
          # This would be implemented with actual LLM call in production
          # For now, simulate with a reasonable response structure
          {
            "diagnosis" => "LLM analysis indicates opportunities for prompt optimization",
            "improvements" => [
              "Add explicit reasoning instructions", 
              "Standardize response format",
              "Optimize token usage"
            ],
            "confidence" => 0.75,
            "reasoning" => "Based on trace analysis, prompts show potential for improvement through genetic optimization",
            "suggested_mutations" => ["expand", "rewrite"],
            "insights" => {
              "pattern_detected" => "optimization_potential",
              "optimization_opportunity" => "instruction_clarity"
            }
          }.to_json
        end
        
        # Format traces for inclusion in prompt
        sig { params(traces: T::Array[ExecutionTrace]).returns(String) }
        def format_traces_for_prompt(traces)
          traces.map.with_index do |trace, idx|
            prompt_preview = truncate_text(trace.prompt_text || 'N/A', 100)
            response_preview = truncate_text(trace.response_text || 'N/A', 100)
            "#{idx + 1}. [#{trace.event_name}] #{prompt_preview} → #{response_preview}"
          end.join("\n")
        end
        
        # Estimate token usage from response
        sig { params(text: String).returns(Integer) }
        def estimate_token_usage(text)
          # Rough estimation: ~4 characters per token
          (text.length / 4.0).ceil
        end
        
        # Analyze token efficiency patterns
        sig { params(llm_traces: T::Array[ExecutionTrace]).returns(T::Hash[Symbol, T.untyped]) }
        def analyze_token_efficiency(llm_traces)
          return { status: 'no_data', suggestions: [] } if llm_traces.empty?
          
          total_tokens = llm_traces.sum(&:token_usage)
          avg_tokens = total_tokens.to_f / llm_traces.size
          
          if avg_tokens > 400
            {
              status: 'poor',
              average_tokens: avg_tokens,
              suggestions: ['Consider reducing prompt length', 'Optimize instruction clarity']
            }
          elsif avg_tokens > 200
            {
              status: 'moderate',
              average_tokens: avg_tokens,
              suggestions: ['Monitor token usage trends', 'Consider prompt optimization']
            }
          else
            {
              status: 'good',
              average_tokens: avg_tokens,
              suggestions: ['Token usage appears efficient']
            }
          end
        end
        
        # Analyze response quality patterns
        sig { params(llm_traces: T::Array[ExecutionTrace]).returns(T::Hash[Symbol, T.untyped]) }
        def analyze_response_quality(llm_traces)
          return { consistency: 'no_data', recommendations: [] } if llm_traces.empty?
          
          response_lengths = llm_traces.map { |t| t.response_text&.length || 0 }
          length_variance = calculate_variance(response_lengths)
          
          if length_variance > 1000
            {
              consistency: 'inconsistent',
              variance: length_variance,
              recommendations: [
                'Add response format guidelines',
                'Consider structured output templates'
              ]
            }
          else
            {
              consistency: 'consistent',
              variance: length_variance,
              recommendations: ['Response quality appears consistent']
            }
          end
        end
        
        # Analyze model consistency
        sig { params(llm_traces: T::Array[ExecutionTrace]).returns(T::Hash[Symbol, T.untyped]) }
        def analyze_model_consistency(llm_traces)
          models = llm_traces.map(&:model_name).compact.uniq
          
          {
            unique_models: models.size,
            models_used: models,
            recommendation: models.size > 1 ? 'Consider using single model for consistency' : 'Model usage is consistent'
          }
        end
        
        # Adjust mutations based on history to avoid repetition
        sig { params(suggested: T::Array[Symbol], history: T::Array[Symbol], trend: T.nilable(String)).returns(T::Array[Symbol]) }
        def adjust_mutations_for_history(suggested, history, trend)
          # Count recent usage of each mutation type
          recent_usage = history.last(5).tally
          
          # Filter out overused mutations
          adjusted = suggested.reject do |mutation|
            recent_usage[mutation] && recent_usage[mutation] >= 2
          end
          
          # If trend is declining, prefer different strategies
          if trend == 'declining'
            adjusted = adjusted.reject { |m| m == :expand } # Avoid expansion if performance declining
            adjusted += [:simplify, :rephrase] unless adjusted.include?(:simplify) || adjusted.include?(:rephrase)
          end
          
          # Ensure we always have at least one suggestion
          adjusted.empty? ? [:rewrite] : adjusted.uniq
        end
        
        # Calculate variance for array of numbers
        sig { params(values: T::Array[Integer]).returns(Float) }
        def calculate_variance(values)
          return 0.0 if values.size < 2
          
          mean = values.sum.to_f / values.size
          sum_squared_diff = values.sum { |v| (v - mean) ** 2 }
          sum_squared_diff / values.size
        end
        
        # Truncate text to specified length with ellipsis
        sig { params(text: String, length: Integer).returns(String) }
        def truncate_text(text, length)
          return text if text.length <= length
          "#{text[0...length]}..."
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

        # Create program copy with modified instruction using DSPy.rb dynamic capabilities
        sig { params(original_program: T.untyped, new_instruction: String).returns(T.untyped) }
        def create_program_with_instruction(original_program, new_instruction)
          case original_program
          when DSPy::Predict
            # DSPy::Predict has built-in support for instruction modification
            original_program.with_instruction(new_instruction)
          when DSPy::Module
            # For custom DSPy::Module classes, create new instance with updated predictors
            create_modified_module(original_program, new_instruction)
          else
            # For other types (like test doubles), check available methods
            if original_program.respond_to?(:with_instruction)
              original_program.with_instruction(new_instruction)
            elsif original_program.respond_to?(:signature_class)
              # Create new DSPy::Predict with the same signature but new instruction
              signature_class = original_program.signature_class
              DSPy::Predict.new(signature_class).with_instruction(new_instruction)
            else
              # Fallback: return original if we can't modify
              original_program
            end
          end
        rescue => e
          # Return original program on error
          original_program
        end

        # Create modified version of custom DSPy::Module (for GeneticEngine)
        sig { params(original_module: DSPy::Module, new_instruction: String).returns(DSPy::Module) }
        def create_modified_module(original_module, new_instruction)
          begin
            # Create a new instance of the same class
            new_module = original_module.class.new
            
            # Try to find and update any internal predictors
            original_module.instance_variables.each do |var_name|
              var_value = original_module.instance_variable_get(var_name)
              
              if var_value.is_a?(DSPy::Predict)
                # Update the instruction for internal predictors
                modified_predictor = var_value.with_instruction(new_instruction)
                new_module.instance_variable_set(var_name, modified_predictor)
              else
                # Copy other instance variables as-is
                new_module.instance_variable_set(var_name, var_value)
              end
            end
            
            new_module
          rescue => e
            # Fallback to original module
            original_module
          end
        end
      end

      # FitnessScore represents multi-dimensional evaluation results
      class FitnessScore < T::Struct
        extend T::Sig

        const :primary_score, Float
        const :secondary_scores, T::Hash[Symbol, Float]
        const :overall_score, Float
        const :metadata, T::Hash[Symbol, T.untyped]

        sig do
          params(
            primary_score: Float,
            secondary_scores: T::Hash[Symbol, Float],
            overall_score: Float,
            metadata: T.nilable(T::Hash[Symbol, T.untyped])
          ).void
        end
        def initialize(primary_score:, secondary_scores:, overall_score:, metadata: nil)
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

      # InstructionProposer: Analyzes execution traces and generates improved instructions using LLM reflection
      class InstructionProposer
        extend T::Sig

        sig { params(config: GEPAConfig).void }
        def initialize(config:)
          @config = config
        end

        # Generate improved instruction based on execution traces and failures
        sig { params(original_instruction: String, execution_traces: T::Array[ExecutionTrace], failed_examples: T::Array[T.untyped]).returns(String) }
        def propose_instruction(original_instruction:, execution_traces:, failed_examples:)
          if execution_traces.empty? && failed_examples.empty?
            # No traces or failures to analyze, return original
            return original_instruction
          end

          # Use LLM-based reflection to generate improved instruction
          reflect_and_propose(
            original_instruction: original_instruction,
            execution_traces: execution_traces,
            failed_examples: failed_examples
          )
        rescue => e
          # Fallback to original instruction on error
          original_instruction
        end

        private

        sig { returns(GEPAConfig) }
        attr_reader :config

        # Use LLM reflection to propose improved instruction
        sig { params(original_instruction: String, execution_traces: T::Array[ExecutionTrace], failed_examples: T::Array[T.untyped]).returns(String) }
        def reflect_and_propose(original_instruction:, execution_traces:, failed_examples:)
          # Create signature for instruction improvement
          improvement_signature = create_instruction_improvement_signature

          # Create predictor for instruction proposal
          proposer = DSPy::Predict.new(improvement_signature)

          # Analyze traces and failures
          trace_analysis = analyze_execution_traces(execution_traces)
          failure_analysis = analyze_failed_examples(failed_examples)

          # Generate improved instruction
          result = proposer.call(
            original_instruction: original_instruction,
            trace_analysis: trace_analysis,
            failure_analysis: failure_analysis,
            improvement_context: "GEPA prompt optimization for better performance"
          )

          result.improved_instruction || original_instruction
        rescue => e
          # Return original instruction if LLM call fails
          original_instruction
        end

        # Create signature for instruction improvement
        sig { returns(T.class_of(DSPy::Signature)) }
        def create_instruction_improvement_signature
          Class.new(DSPy::Signature) do
            description "Analyze execution traces and propose improved instructions for better AI system performance"

            input do
              const :original_instruction, String, description: "The current instruction/prompt being used"
              const :trace_analysis, String, description: "Analysis of execution traces showing patterns and issues"
              const :failure_analysis, String, description: "Analysis of failed examples and their patterns"
              const :improvement_context, String, description: "Context about what kind of improvement is needed"
            end

            output do
              const :improved_instruction, String, description: "Improved instruction that addresses identified issues"
              const :reasoning, String, description: "Explanation of why this improvement should work better"
              const :confidence, Float, description: "Confidence in the improvement (0.0-1.0)"
            end
          end
        end

        # Analyze execution traces to identify patterns
        sig { params(traces: T::Array[ExecutionTrace]).returns(String) }
        def analyze_execution_traces(traces)
          return "No execution traces available" if traces.empty?

          llm_traces = traces.select(&:llm_trace?)
          module_traces = traces.select(&:module_trace?)

          analysis = []
          analysis << "Execution Trace Analysis:"
          analysis << "- Total traces: #{traces.size}"
          analysis << "- LLM interactions: #{llm_traces.size}"
          analysis << "- Module calls: #{module_traces.size}"

          if llm_traces.any?
            token_usage = llm_traces.sum(&:token_usage)
            avg_response_length = llm_traces.map { |t| t.attributes['response']&.to_s&.length || 0 }.sum / llm_traces.size
            
            analysis << "- Total tokens used: #{token_usage}"
            analysis << "- Average response length: #{avg_response_length} characters"
            
            # Identify models used
            models = llm_traces.map { |t| t.attributes['gen_ai.request.model'] }.compact.uniq
            analysis << "- Models used: #{models.join(', ')}" if models.any?
          end

          # Analyze timing patterns
          if traces.size > 1
            timespan = traces.max_by(&:timestamp).timestamp - traces.min_by(&:timestamp).timestamp
            analysis << "- Execution timespan: #{timespan.round(2)} seconds"
          end

          analysis.join("\n")
        end

        # Analyze failed examples to identify failure patterns
        sig { params(failed_examples: T::Array[T.untyped]).returns(String) }
        def analyze_failed_examples(failed_examples)
          return "No failed examples to analyze" if failed_examples.empty?

          analysis = []
          analysis << "Failure Pattern Analysis:"
          analysis << "- Failed examples count: #{failed_examples.size}"

          # Group failures by type if possible
          if failed_examples.first.respond_to?(:input)
            input_patterns = failed_examples.map { |ex| ex.input.keys }.flatten.uniq
            analysis << "- Input fields involved: #{input_patterns.join(', ')}"
          end

          # Sample some failure cases for context
          sample_size = [failed_examples.size, 3].min
          analysis << "- Sample failures:"
          failed_examples.take(sample_size).each_with_index do |example, idx|
            if example.respond_to?(:input) && example.respond_to?(:expected_values)
              input_summary = example.input.values.first.to_s[0..50] + "..."
              expected = example.expected_values.values.first.to_s[0..30] + "..."
              analysis << "  #{idx + 1}. Input: #{input_summary} | Expected: #{expected}"
            end
          end

          analysis.join("\n")
        end
      end

      # MutationEngine: Handles LLM-based prompt transformations for genetic evolution
      class MutationEngine
        extend T::Sig

        sig { returns(GEPAConfig) }
        attr_reader :config

        sig { returns(InstructionProposer) }
        attr_reader :instruction_proposer

        sig { params(config: GEPAConfig).void }
        def initialize(config:)
          @config = config
          @instruction_proposer = InstructionProposer.new(config: config)
        end

        # Mutate a single program with LLM-based instruction proposal
        sig { params(program: T.untyped, execution_traces: T::Array[ExecutionTrace], failed_examples: T::Array[T.untyped]).returns(T.untyped) }
        def mutate_program(program, execution_traces: [], failed_examples: [])
          return program if rand > @config.mutation_rate

          begin
            original_instruction = extract_instruction(program)
            
            # Use LLM-based instruction proposal instead of hardcoded mutations
            improved_instruction = @instruction_proposer.propose_instruction(
              original_instruction: original_instruction,
              execution_traces: execution_traces,
              failed_examples: failed_examples
            )
            
            create_mutated_program(program, improved_instruction)
          rescue => e
            emit_event('mutation_error', {
              error: e.message,
              program_type: program.class.name
            })
            # Return original program on mutation failure
            program
          end
        end

        # Batch mutation of multiple programs with shared execution context
        sig { params(programs: T::Array[T.untyped], execution_traces: T::Array[ExecutionTrace], failed_examples: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def batch_mutate(programs, execution_traces: [], failed_examples: [])
          return [] if programs.empty?
          
          programs.map { |program| mutate_program(program, execution_traces: execution_traces, failed_examples: failed_examples) }
        end

        # Emit events for logging and monitoring
        sig { params(event_name: String, data: T::Hash[Symbol, T.untyped]).void }
        def emit_event(event_name, data = {})
          # For now, just a placeholder - could integrate with DSPy event system
          # In full implementation, this would emit events for monitoring
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
        sig { params(instruction: String, mutation_type: MutationType).returns(String) }
        def apply_mutation(instruction, mutation_type)
          case mutation_type
          when MutationType::Rewrite
            apply_rewrite_mutation(instruction)
          when MutationType::Expand
            apply_expand_mutation(instruction)
          when MutationType::Simplify
            apply_simplify_mutation(instruction)
          when MutationType::Combine
            apply_combine_mutation(instruction)
          when MutationType::Rephrase
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
          case original_program
          when DSPy::Predict
            # DSPy::Predict has built-in support for instruction modification
            original_program.with_instruction(new_instruction)
          when DSPy::Module
            # For custom DSPy::Module classes, we need to create a new instance
            # and update any internal predictors that have instruction-based signatures
            create_mutated_module(original_program, new_instruction)
          else
            # For other types (like test doubles), check if they respond to with_instruction
            if original_program.respond_to?(:with_instruction)
              original_program.with_instruction(new_instruction)
            elsif original_program.respond_to?(:signature_class)
              # Try to create a new DSPy::Predict with the same signature but new instruction
              signature_class = original_program.signature_class
              DSPy::Predict.new(signature_class).with_instruction(new_instruction)
            else
              # Fallback: return original if we can't mutate
              emit_event('mutation_fallback', {
                program_type: original_program.class.name,
                reason: 'No mutation method available'
              })
              original_program
            end
          end
        rescue => e
          emit_event('mutation_error', {
            error: e.message,
            program_type: original_program.class.name,
            backtrace: e.backtrace&.first(3)
          })
          # Return original program on error
          original_program
        end

        # Create mutated version of custom DSPy::Module
        sig { params(original_module: DSPy::Module, new_instruction: String).returns(DSPy::Module) }
        def create_mutated_module(original_module, new_instruction)
          # For custom modules, we need to create a new instance
          # This is a simplified approach - in practice, modules might need
          # more sophisticated copying of their internal state
          begin
            # Create a new instance of the same class
            new_module = original_module.class.new
            
            # Try to find and update any internal predictors
            original_module.instance_variables.each do |var_name|
              var_value = original_module.instance_variable_get(var_name)
              
              if var_value.is_a?(DSPy::Predict)
                # Update the instruction for internal predictors
                mutated_predictor = var_value.with_instruction(new_instruction)
                new_module.instance_variable_set(var_name, mutated_predictor)
              else
                # Copy other instance variables as-is
                new_module.instance_variable_set(var_name, var_value)
              end
            end
            
            new_module
          rescue => e
            emit_event('module_mutation_error', {
              error: e.message,
              module_class: original_module.class.name
            })
            # Fallback to original module
            original_module
          end
        end

        # Select mutation type based on context and configuration
        sig { params(instruction: T.nilable(String)).returns(MutationType) }
        def select_mutation_type(instruction = nil)
          # Adaptive selection based on instruction characteristics
          if instruction && instruction.length < 20
            # Short instructions benefit from expansion
            [MutationType::Expand, MutationType::Combine].sample
          elsif instruction && instruction.length > 100
            # Long instructions benefit from simplification
            [MutationType::Simplify, MutationType::Rephrase].sample
          else
            # Balanced selection from all types
            @config.mutation_types.sample
          end
        end

        # Calculate diversity of mutations applied
        sig { params(mutations: T::Array[MutationType]).returns(Float) }
        def mutation_diversity(mutations)
          return 0.0 if mutations.empty?
          
          unique_types = mutations.uniq.size
          total_types = @config.mutation_types.size
          
          unique_types.to_f / total_types
        end
      end

      # CrossoverEngine: Handles genetic recombination of prompts for diversity
      class CrossoverEngine
        extend T::Sig

        # Struct for instruction components
        class InstructionComponents < T::Struct
          prop :action, String
          prop :modifiers, String
        end

        sig { returns(GEPAConfig) }
        attr_reader :config

        sig { params(config: GEPAConfig).void }
        def initialize(config:)
          @config = config
        end

        # Perform crossover between two parent programs
        sig { params(parent_a: T.untyped, parent_b: T.untyped).returns(T::Array[T.untyped]) }
        def crossover_programs(parent_a, parent_b)
          return [parent_a, parent_b] if rand > @config.crossover_rate

          begin
            instruction_a = extract_instruction(parent_a)
            instruction_b = extract_instruction(parent_b)
            
            crossover_type = select_crossover_type(instruction_a, instruction_b)
            offspring_instructions = apply_crossover(instruction_a, instruction_b, crossover_type)
            
            offspring = [
              create_crossover_program(parent_a, offspring_instructions[0]),
              create_crossover_program(parent_b, offspring_instructions[1])
            ]
            
            offspring
          rescue => e
            # Return original parents on crossover failure
            [parent_a, parent_b]
          end
        end

        # Batch crossover for entire population
        sig { params(population: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def batch_crossover(population)
          return [] if population.empty?
          return [population.first] if population.size == 1
          
          offspring = []
          
          # Pair up population for crossover
          population.each_slice(2) do |pair|
            if pair.size == 2
              crossed = crossover_programs(pair[0], pair[1])
              offspring.concat(crossed)
            else
              offspring << pair[0] # Unpaired individual passes through
            end
          end
          
          offspring
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

        # Apply specific crossover type to two instructions
        sig { params(instruction_a: String, instruction_b: String, crossover_type: CrossoverType).returns(T::Array[String]) }
        def apply_crossover(instruction_a, instruction_b, crossover_type)
          case crossover_type
          when CrossoverType::Uniform
            uniform_crossover(instruction_a, instruction_b)
          when CrossoverType::Blend
            blend_crossover(instruction_a, instruction_b)
          when CrossoverType::Structured
            structured_crossover(instruction_a, instruction_b)
          else
            [instruction_a, instruction_b]
          end
        end

        # Uniform crossover: Exchange elements randomly at word level
        sig { params(instruction_a: String, instruction_b: String).returns(T::Array[String]) }
        def uniform_crossover(instruction_a, instruction_b)
          return [instruction_a, instruction_b] if instruction_a == instruction_b
          
          words_a = instruction_a.split
          words_b = instruction_b.split
          
          # Create offspring by randomly selecting words from parents
          offspring_a_words = []
          offspring_b_words = []
          
          max_length = [words_a.size, words_b.size].max
          
          max_length.times do |i|
            word_a = words_a[i]
            word_b = words_b[i]
            
            if rand < 0.5
              offspring_a_words << (word_a || word_b)
              offspring_b_words << (word_b || word_a)
            else
              offspring_a_words << (word_b || word_a)
              offspring_b_words << (word_a || word_b)
            end
          end
          
          [
            offspring_a_words.compact.join(' '),
            offspring_b_words.compact.join(' ')
          ]
        end

        # Blend crossover: Semantically combine instructions
        sig { params(instruction_a: String, instruction_b: String).returns(T::Array[String]) }
        def blend_crossover(instruction_a, instruction_b)
          # Simple blending patterns - in full implementation would use LLM
          patterns = [
            -> (a, b) { "#{a} and #{b}" },
            -> (a, b) { "#{a}, specifically #{b}" },
            -> (a, b) { "#{b} while #{a.downcase}" },
            -> (a, b) { "Combine #{a.downcase} with #{b.downcase}" }
          ]
          
          pattern = patterns.sample
          
          [
            pattern.call(instruction_a, instruction_b),
            pattern.call(instruction_b, instruction_a)
          ]
        end

        # Structured crossover: Maintain grammatical and logical structure
        sig { params(instruction_a: String, instruction_b: String).returns(T::Array[String]) }
        def structured_crossover(instruction_a, instruction_b)
          # Extract structural components
          components_a = extract_components(instruction_a)
          components_b = extract_components(instruction_b)
          
          # Cross structural components
          offspring_a = combine_components(components_a.action, components_b.modifiers)
          offspring_b = combine_components(components_b.action, components_a.modifiers)
          
          [offspring_a, offspring_b]
        end

        # Extract structural components from instruction
        sig { params(instruction: String).returns(InstructionComponents) }
        def extract_components(instruction)
          words = instruction.split
          
          # Simple heuristic: first verb-like word is action, rest are modifiers
          action_idx = words.find_index { |word| verb_like?(word) } || 0
          
          InstructionComponents.new(
            action: words[action_idx] || words.first || "complete",
            modifiers: (words - [words[action_idx]]).join(' ')
          )
        end

        # Combine action and modifiers into coherent instruction
        sig { params(action: String, modifiers: String).returns(String) }
        def combine_components(action, modifiers)
          if modifiers.empty?
            "#{action.capitalize} the task"
          else
            "#{action.capitalize} #{modifiers}"
          end
        end

        # Simple heuristic to identify verb-like words
        sig { params(word: String).returns(T::Boolean) }
        def verb_like?(word)
          verb_patterns = %w[solve answer calculate determine analyze compute resolve examine]
          verb_patterns.any? { |pattern| word.downcase.include?(pattern) }
        end

        # Create new program with crossover instruction
        sig { params(original_program: T.untyped, new_instruction: String).returns(T.untyped) }
        def create_crossover_program(original_program, new_instruction)
          # For now, return the original program as we don't modify instruction in place
          # In full implementation, would create new program instance with modified instruction
          original_program
        end

        # Select crossover type based on instruction characteristics
        sig { params(instruction_a: T.nilable(String), instruction_b: T.nilable(String)).returns(CrossoverType) }
        def select_crossover_type(instruction_a = nil, instruction_b = nil)
          # Adaptive selection based on instruction characteristics
          if instruction_a && instruction_b
            combined_length = instruction_a.length + instruction_b.length
            
            if combined_length < 40
              # Short instructions benefit from blending
              [CrossoverType::Blend, CrossoverType::Uniform].sample
            elsif combined_length > 200
              # Long instructions benefit from structured crossover
              [CrossoverType::Structured, CrossoverType::Uniform].sample
            else
              # Balanced selection
              @config.crossover_types.sample
            end
          else
            @config.crossover_types.sample
          end
        end

        # Calculate diversity of crossover operations
        sig { params(crossovers: T::Array[CrossoverType]).returns(Float) }
        def crossover_diversity(crossovers)
          return 0.0 if crossovers.empty?
          
          unique_types = crossovers.uniq.size
          total_types = @config.crossover_types.size
          
          unique_types.to_f / total_types
        end
      end

      # ParetoSelector: Multi-objective optimization using Pareto frontier analysis
      class ParetoSelector
        extend T::Sig

        sig { returns(FitnessEvaluator) }
        attr_reader :evaluator

        sig { returns(GEPAConfig) }
        attr_reader :config

        sig { params(evaluator: FitnessEvaluator, config: GEPAConfig).void }
        def initialize(evaluator:, config:)
          @evaluator = evaluator
          @config = config
        end

        # Select parents for breeding using Pareto-based selection
        sig { params(population_with_scores: T::Array[T::Array[T.untyped]], count: Integer).returns(T::Array[T.untyped]) }
        def select_parents(population_with_scores, count:)
          return [] if population_with_scores.empty?
          return population_with_scores.map(&:first) if count >= population_with_scores.size
          
          # Combine tournament and Pareto-based selection for parent selection
          selected = []
          
          count.times do
            parent = tournament_selection(population_with_scores)
            selected << parent
          end
          
          selected
        end

        # Select survivors for next generation balancing elite and diversity
        sig { params(population_with_scores: T::Array[T::Array[T.untyped]], count: Integer).returns(T::Array[T.untyped]) }
        def select_survivors(population_with_scores, count:)
          return [] if population_with_scores.empty?
          return population_with_scores.map(&:first) if count >= population_with_scores.size
          
          scores = population_with_scores.map(&:last)
          
          # Find Pareto frontier first
          pareto_frontier = find_pareto_frontier(scores)
          frontier_indices = scores.each_index.select { |i| pareto_frontier.include?(scores[i]) }
          frontier_programs = frontier_indices.map { |i| population_with_scores[i].first }
          
          if frontier_programs.size >= count
            # Use diversity selection within frontier
            frontier_with_scores = frontier_indices.map { |i| population_with_scores[i] }
            return diversity_selection(frontier_with_scores, count: count)
          else
            # Include all frontier + fill remaining with elite selection
            remaining_count = count - frontier_programs.size
            remaining_population = population_with_scores.reject.with_index { |_, i| frontier_indices.include?(i) }
            
            additional = elite_selection(remaining_population, count: remaining_count)
            frontier_programs + additional
          end
        end

        private

        # Find Pareto frontier (non-dominated solutions)
        sig { params(fitness_scores: T::Array[FitnessScore]).returns(T::Array[FitnessScore]) }
        def find_pareto_frontier(fitness_scores)
          return [] if fitness_scores.empty?
          return fitness_scores if fitness_scores.size == 1
          
          frontier = []
          
          fitness_scores.each do |candidate|
            # Check if candidate is dominated by any other solution
            is_dominated = fitness_scores.any? do |other|
              other != candidate && candidate.dominated_by?(other)
            end
            
            frontier << candidate unless is_dominated
          end
          
          frontier
        end

        # Calculate crowding distance for diversity preservation
        sig { params(fitness_scores: T::Array[FitnessScore]).returns(T::Hash[FitnessScore, Float]) }
        def calculate_crowding_distance(fitness_scores)
          distances = {}
          
          # Initialize distances for all solutions
          fitness_scores.each { |score| distances[score] = 0.0 }
          
          return distances if fitness_scores.size <= 2
          
          # Calculate crowding distance for each objective
          objectives = [:primary_score, :overall_score]
          secondary_objectives = fitness_scores.first.secondary_scores.keys
          all_objectives = objectives + secondary_objectives
          
          all_objectives.each do |objective|
            # Sort by current objective
            sorted_scores = fitness_scores.sort_by do |score|
              case objective
              when :primary_score
                score.primary_score
              when :overall_score
                score.overall_score
              else
                score.secondary_scores[objective] || 0.0
              end
            end
            
            # Set boundary solutions to high distance
            distances[sorted_scores.first] = Float::INFINITY if sorted_scores.size > 0
            distances[sorted_scores.last] = Float::INFINITY if sorted_scores.size > 1
            
            next if sorted_scores.size <= 2
            
            # Calculate range for normalization
            min_val = get_objective_value(sorted_scores.first, objective)
            max_val = get_objective_value(sorted_scores.last, objective)
            range = max_val - min_val
            
            next if range <= 0
            
            # Calculate crowding distance for intermediate solutions
            (1...(sorted_scores.size - 1)).each do |i|
              prev_val = get_objective_value(sorted_scores[i - 1], objective)
              next_val = get_objective_value(sorted_scores[i + 1], objective)
              
              distances[sorted_scores[i]] += (next_val - prev_val) / range
            end
          end
          
          distances
        end

        # Get objective value from fitness score
        sig { params(score: FitnessScore, objective: Symbol).returns(Float) }
        def get_objective_value(score, objective)
          case objective
          when :primary_score
            score.primary_score
          when :overall_score
            score.overall_score
          else
            score.secondary_scores[objective] || 0.0
          end
        end

        # Tournament selection with Pareto preference
        sig { params(population_with_scores: T::Array[T::Array[T.untyped]]).returns(T.untyped) }
        def tournament_selection(population_with_scores)
          return population_with_scores.first.first if population_with_scores.size == 1
          
          tournament_size = [3, population_with_scores.size].min
          tournament = population_with_scores.sample(tournament_size)
          
          # Select best from tournament based on Pareto dominance and crowding
          best_program, best_score = tournament.first
          
          tournament[1..].each do |program, score|
            if score.dominated_by?(best_score)
              # Current best dominates this candidate, keep current
              next
            elsif best_score.dominated_by?(score)
              # This candidate dominates current best, replace
              best_program, best_score = program, score
            else
              # Non-dominated comparison, use overall score as tiebreaker
              if score.overall_score > best_score.overall_score
                best_program, best_score = program, score
              end
            end
          end
          
          best_program
        end

        # Diversity-based selection using crowding distance
        sig { params(population_with_scores: T::Array[T::Array[T.untyped]], count: Integer).returns(T::Array[T.untyped]) }
        def diversity_selection(population_with_scores, count:)
          return population_with_scores.map(&:first) if count >= population_with_scores.size
          
          scores = population_with_scores.map(&:last)
          distances = calculate_crowding_distance(scores)
          
          # Sort by crowding distance (descending - prefer more diverse)
          sorted_pairs = population_with_scores.sort_by { |_, score| -distances[score] }
          
          sorted_pairs.take(count).map(&:first)
        end

        # Elite selection based on overall fitness
        sig { params(population_with_scores: T::Array[T::Array[T.untyped]], count: Integer).returns(T::Array[T.untyped]) }
        def elite_selection(population_with_scores, count:)
          return population_with_scores.map(&:first) if count >= population_with_scores.size
          
          # Sort by overall score (descending - best first)
          sorted_pairs = population_with_scores.sort_by { |_, score| -score.overall_score }
          
          sorted_pairs.take(count).map(&:first)
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
        sig { returns(T::Array[MutationType]) }
        attr_accessor :mutation_types
        sig { returns(Float) }
        attr_accessor :crossover_rate
        sig { returns(T::Array[CrossoverType]) }
        attr_accessor :crossover_types

        sig { void }
        def initialize
          super
          @reflection_lm = 'gpt-4o'
          @num_generations = 10
          @population_size = 8
          @mutation_rate = 0.7
          @use_pareto_selection = true
          @simple_mode = false
          @mutation_types = [MutationType::Rewrite, MutationType::Expand, MutationType::Simplify, MutationType::Combine, MutationType::Rephrase]
          @crossover_rate = 0.6
          @crossover_types = [CrossoverType::Uniform, CrossoverType::Blend, CrossoverType::Structured]
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
            mutation_types: @mutation_types,
            crossover_rate: @crossover_rate,
            crossover_types: @crossover_types
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
            # Phase 2 - Full GEPA genetic algorithm implementation
            perform_gepa_optimization(program, trainset, valset)
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

      # Create a new program instance with modified instruction using DSPy.rb dynamic capabilities
      sig { params(original_program: T.untyped, new_instruction: String).returns(T.untyped) }
      def create_program_with_instruction(original_program, new_instruction)
        case original_program
        when DSPy::Predict
          # DSPy::Predict has built-in support for instruction modification
          original_program.with_instruction(new_instruction)
        when DSPy::Module
          # For custom DSPy::Module classes, create new instance with updated predictors
          create_modified_module_instance(original_program, new_instruction)
        else
          # For other types (like test doubles), check available methods
          if original_program.respond_to?(:with_instruction)
            original_program.with_instruction(new_instruction)
          elsif original_program.respond_to?(:signature_class)
            # Create new DSPy::Predict with the same signature but new instruction
            signature_class = original_program.signature_class
            DSPy::Predict.new(signature_class).with_instruction(new_instruction)
          else
            # Fallback: return original if we can't modify
            emit_event('program_modification_fallback', {
              program_type: original_program.class.name,
              reason: 'No modification method available'
            })
            original_program
          end
        end
      rescue => e
        emit_event('program_modification_error', {
          error: e.message,
          program_type: original_program.class.name
        })
        # Return original program on error
        original_program
      end

      # Create modified version of custom DSPy::Module instance (for main GEPA class)
      sig { params(original_module: DSPy::Module, new_instruction: String).returns(DSPy::Module) }
      def create_modified_module_instance(original_module, new_instruction)
        begin
          # Create a new instance of the same class
          new_module = original_module.class.new
          
          # Try to find and update any internal predictors
          original_module.instance_variables.each do |var_name|
            var_value = original_module.instance_variable_get(var_name)
            
            if var_value.is_a?(DSPy::Predict)
              # Update the instruction for internal predictors
              modified_predictor = var_value.with_instruction(new_instruction)
              new_module.instance_variable_set(var_name, modified_predictor)
            else
              # Copy other instance variables as-is
              new_module.instance_variable_set(var_name, var_value)
            end
          end
          
          new_module
        rescue => e
          emit_event('module_modification_error', {
            error: e.message,
            module_class: original_module.class.name
          })
          # Fallback to original module
          original_module
        end
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
      
      # Complete GEPA genetic algorithm optimization
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).returns(OptimizationResult)
      end
      def perform_gepa_optimization(program, trainset, valset)
        # Initialize all GEPA components
        fitness_evaluator = create_fitness_evaluator
        genetic_engine = create_genetic_engine(fitness_evaluator)
        reflection_engine = create_reflection_engine
        mutation_engine = create_mutation_engine
        crossover_engine = create_crossover_engine
        pareto_selector = create_pareto_selector(fitness_evaluator)
        
        # Initialize trace collection for reflection
        trace_collector = TraceCollector.new
        optimization_run_id = "gepa-run-#{SecureRandom.hex(4)}"
        
        emit_event('gepa_optimization_start', {
          optimization_run_id: optimization_run_id,
          num_generations: @config.num_generations,
          population_size: @config.population_size,
          mutation_rate: @config.mutation_rate,
          crossover_rate: @config.crossover_rate
        })
        
        begin
          # Run the complete genetic algorithm evolution
          evolution_result = genetic_engine.run_evolution(program, trainset)
          
          # Collect traces for reflection analysis
          execution_traces = trace_collector.traces_for_run(optimization_run_id)
          
          # Generate reflection insights on the optimization process
          reflection_result = reflection_engine.reflect_with_llm(execution_traces)
          
          # Evaluate final candidate on validation set if provided
          final_validation_score = if valset && !valset.empty?
            validation_fitness = fitness_evaluator.evaluate_candidate(evolution_result[:best_candidate], valset)
            validation_fitness.overall_score
          else
            evolution_result[:best_fitness].overall_score
          end
          
          emit_event('gepa_optimization_complete', {
            optimization_run_id: optimization_run_id,
            best_fitness: evolution_result[:best_fitness].overall_score,
            final_generation: evolution_result[:generation_count],
            validation_score: final_validation_score,
            reflection_confidence: reflection_result.confidence
          })
          
          # Create comprehensive optimization result
          OptimizationResult.new(
            optimized_program: evolution_result[:best_candidate],
            scores: {
              fitness_score: evolution_result[:best_fitness].overall_score,
              validation_score: final_validation_score,
              primary_score: evolution_result[:best_fitness].primary_score,
              **evolution_result[:best_fitness].secondary_scores
            },
            history: {
              num_generations: evolution_result[:generation_count],
              population_size: @config.population_size,
              generation_history: evolution_result[:generation_history],
              final_population: evolution_result[:final_population],
              phase: 'Phase 2 - Complete GEPA',
              mutation_rate: @config.mutation_rate,
              crossover_rate: @config.crossover_rate,
              selection_strategy: @config.use_pareto_selection ? 'pareto' : 'tournament'
            },
            best_score_name: 'fitness_score',
            best_score_value: evolution_result[:best_fitness].overall_score,
            metadata: {
              optimizer: 'GEPA',
              reflection_lm: @config.reflection_lm,
              implementation_status: 'Phase 2 - Complete Implementation',
              optimization_run_id: optimization_run_id,
              reflection_insights: {
                diagnosis: reflection_result.diagnosis,
                improvements: reflection_result.improvements,
                confidence: reflection_result.confidence,
                suggested_mutations: reflection_result.suggested_mutations
              },
              trace_analysis: {
                total_traces: execution_traces.size,
                llm_traces: execution_traces.count(&:llm_trace?),
                module_traces: execution_traces.count(&:module_trace?),
                execution_timespan: calculate_execution_timespan(execution_traces)
              },
              component_versions: {
                genetic_engine: 'v2.0',
                fitness_evaluator: 'v2.0', 
                reflection_engine: 'v2.0',
                mutation_engine: 'v2.0',
                crossover_engine: 'v2.0',
                pareto_selector: 'v2.0'
              }
            }
          )
          
        rescue => e
          emit_event('gepa_optimization_error', {
            optimization_run_id: optimization_run_id,
            error: e.message,
            backtrace: e.backtrace&.take(5)
          })
          
          # Return fallback result on optimization failure
          fallback_fitness = fitness_evaluator.evaluate_candidate(program, trainset)
          
          OptimizationResult.new(
            optimized_program: program,
            scores: { 
              fitness_score: fallback_fitness.overall_score,
              primary_score: fallback_fitness.primary_score,
              **fallback_fitness.secondary_scores
            },
            history: {
              num_generations: 0,
              population_size: @config.population_size,
              phase: 'Phase 2 - Error Recovery',
              error: e.message
            },
            best_score_name: 'fitness_score', 
            best_score_value: fallback_fitness.overall_score,
            metadata: {
              optimizer: 'GEPA',
              reflection_lm: @config.reflection_lm,
              implementation_status: 'Phase 2 - Error Recovery',
              optimization_run_id: optimization_run_id,
              error_details: {
                message: e.message,
                class: e.class.name,
                recovery_strategy: 'fallback_to_original'
              }
            }
          )
        end
      end
      
      # Create and configure fitness evaluator
      sig { returns(FitnessEvaluator) }
      def create_fitness_evaluator
        FitnessEvaluator.new(primary_metric: @metric, config: @config)
      end
      
      # Create and configure genetic engine
      sig { params(fitness_evaluator: FitnessEvaluator).returns(GeneticEngine) }
      def create_genetic_engine(fitness_evaluator)
        GeneticEngine.new(config: @config, metric: @metric)
      end
      
      # Create and configure reflection engine
      sig { returns(ReflectionEngine) }
      def create_reflection_engine
        ReflectionEngine.new(@config)
      end
      
      # Create and configure mutation engine  
      sig { returns(MutationEngine) }
      def create_mutation_engine
        MutationEngine.new(config: @config)
      end
      
      # Create and configure crossover engine
      sig { returns(CrossoverEngine) }
      def create_crossover_engine
        CrossoverEngine.new(config: @config)
      end
      
      # Create and configure pareto selector
      sig { params(fitness_evaluator: FitnessEvaluator).returns(ParetoSelector) }
      def create_pareto_selector(fitness_evaluator)
        ParetoSelector.new(evaluator: fitness_evaluator, config: @config)
      end
      
      # Calculate execution timespan from traces
      sig { params(traces: T::Array[ExecutionTrace]).returns(Float) }
      def calculate_execution_timespan(traces)
        return 0.0 if traces.size < 2
        
        timestamps = traces.map(&:timestamp).sort
        (timestamps.last - timestamps.first).to_f
      end
    end
  end
end