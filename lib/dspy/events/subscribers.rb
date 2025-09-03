# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Events
    # Base subscriber class for event-driven patterns
    class BaseSubscriber
      def initialize
        @subscriptions = []
      end
      
      def subscribe
        raise NotImplementedError, "Subclasses must implement #subscribe"
      end
      
      def unsubscribe
        @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
        @subscriptions.clear
      end
      
      protected
      
      def add_subscription(pattern, &block)
        subscription_id = DSPy.events.subscribe(pattern, &block)
        @subscriptions << subscription_id
        subscription_id
      end
    end

    # Token budget tracking subscriber
    class TokenBudgetSubscriber < BaseSubscriber
      attr_reader :total_tokens, :total_cost, :requests_count, :by_model, :by_provider
      
      def initialize(budget_limit: nil, cost_per_1k_tokens: {})
        super()
        @budget_limit = budget_limit
        @cost_per_1k_tokens = cost_per_1k_tokens.merge(default_costs)
        reset_stats
        subscribe
      end
      
      def subscribe
        add_subscription('llm.*') do |event_name, attributes|
          track_token_usage(event_name, attributes)
        end
      end
      
      def budget_exceeded?
        @budget_limit && @total_tokens > @budget_limit
      end
      
      def budget_remaining
        return nil unless @budget_limit
        [@budget_limit - @total_tokens, 0].max
      end
      
      def usage_summary
        {
          total_tokens: @total_tokens,
          total_cost: @total_cost.round(4),
          requests_count: @requests_count,
          budget_limit: @budget_limit,
          budget_remaining: budget_remaining,
          budget_exceeded: budget_exceeded?,
          by_provider: @by_provider,
          by_model: @by_model
        }
      end
      
      def reset_stats
        @total_tokens = 0
        @total_cost = 0.0
        @requests_count = 0
        @by_model = Hash.new { |h, k| h[k] = { tokens: 0, cost: 0.0, requests: 0 } }
        @by_provider = Hash.new { |h, k| h[k] = { tokens: 0, cost: 0.0, requests: 0 } }
      end
      
      private
      
      def track_token_usage(event_name, attributes)
        # Extract token usage from the event
        prompt_tokens = attributes['gen_ai.usage.prompt_tokens'] || 0
        completion_tokens = attributes['gen_ai.usage.completion_tokens'] || 0
        total_event_tokens = prompt_tokens + completion_tokens
        
        return if total_event_tokens == 0
        
        provider = attributes['gen_ai.system'] || 'unknown'
        model = attributes['gen_ai.request.model'] || 'unknown'
        
        # Update totals
        @total_tokens += total_event_tokens
        @requests_count += 1
        
        # Calculate cost
        cost_key = "#{provider}/#{model}"
        cost_per_1k = @cost_per_1k_tokens[cost_key] || @cost_per_1k_tokens[provider] || 0.0
        event_cost = (total_event_tokens / 1000.0) * cost_per_1k
        @total_cost += event_cost
        
        # Update by provider stats
        @by_provider[provider][:tokens] += total_event_tokens
        @by_provider[provider][:cost] += event_cost
        @by_provider[provider][:requests] += 1
        
        # Update by model stats
        @by_model[model][:tokens] += total_event_tokens
        @by_model[model][:cost] += event_cost
        @by_model[model][:requests] += 1
        
        # Check budget limit
        if budget_exceeded?
          DSPy.event('token_budget.exceeded', {
            total_tokens: @total_tokens,
            budget_limit: @budget_limit,
            provider: provider,
            model: model
          })
        end
      end
      
      def default_costs
        {
          # OpenAI pricing (approximate, per 1k tokens)
          'openai/gpt-4' => 0.03,
          'openai/gpt-4-turbo' => 0.01,
          'openai/gpt-3.5-turbo' => 0.002,
          'openai' => 0.02, # fallback
          
          # Anthropic pricing (approximate)
          'anthropic/claude-3-opus' => 0.015,
          'anthropic/claude-3-sonnet' => 0.003,
          'anthropic/claude-3-haiku' => 0.00025,
          'anthropic' => 0.01, # fallback
          
          # Other providers
          'google' => 0.001,
          'azure' => 0.02,
          'groq' => 0.0002,
          'together' => 0.0006,
          'cohere' => 0.0015,
          'ollama' => 0.0, # local models
        }
      end
    end

    # Optimization progress reporter with markdown output
    class OptimizationReporter < BaseSubscriber
      attr_reader :output_path, :trials, :current_optimizer, :start_time
      
      def initialize(output_path: 'optimization_report.md', auto_write: true)
        super()
        @output_path = output_path
        @auto_write = auto_write
        @trials = []
        @current_optimizer = nil
        @start_time = nil
        @best_score = nil
        subscribe
      end
      
      def subscribe
        add_subscription('optimization.*') do |event_name, attributes|
          handle_optimization_event(event_name, attributes)
        end
      end
      
      def generate_report
        markdown = build_markdown_report
        if @auto_write
          File.write(@output_path, markdown)
        end
        markdown
      end
      
      def summary
        return {} if @trials.empty?
        
        scores = @trials.map { |t| t[:score] }.compact
        {
          optimizer: @current_optimizer,
          total_trials: @trials.length,
          best_score: scores.max,
          worst_score: scores.min,
          average_score: scores.empty? ? nil : scores.sum / scores.length.to_f,
          duration_minutes: @start_time ? ((Time.now - @start_time) / 60.0).round(2) : nil,
          successful_trials: @trials.count { |t| t[:score] },
          failed_trials: @trials.count { |t| t[:score].nil? }
        }
      end
      
      private
      
      def handle_optimization_event(event_name, attributes)
        case event_name
        when 'optimization.start', 'optimization.session_start'
          @current_optimizer = attributes[:optimizer_name]
          @start_time = Time.now
          @trials.clear
          @best_score = nil
          
        when 'optimization.trial_complete', 'optimization.trial_end'
          trial_data = {
            trial_number: attributes[:trial_number],
            score: attributes[:score],
            best_score: attributes[:best_score],
            parameters: attributes[:parameters],
            timestamp: attributes[:timestamp] || Time.now,
            duration_ms: attributes[:duration_ms]
          }
          @trials << trial_data
          
          # Update best score
          if trial_data[:score] && (@best_score.nil? || trial_data[:score] > @best_score)
            @best_score = trial_data[:score]
          end
          
          # Auto-generate report after each trial
          generate_report if @auto_write
          
        when 'optimization.complete', 'optimization.session_complete'
          generate_report if @auto_write
        end
      end
      
      def build_markdown_report
        return "# Optimization Report\n\nNo optimization data available.\n" if @trials.empty?
        
        summary_data = summary
        
        report = <<~MD
          # Optimization Report
          
          **Generated**: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}
          
          ## Summary
          
          - **Optimizer**: #{summary_data[:optimizer] || 'Unknown'}
          - **Total Trials**: #{summary_data[:total_trials]}
          - **Best Score**: #{summary_data[:best_score]&.round(4) || 'N/A'}
          - **Average Score**: #{summary_data[:average_score]&.round(4) || 'N/A'}
          - **Duration**: #{summary_data[:duration_minutes] || 'N/A'} minutes
          - **Success Rate**: #{success_rate.round(1)}%
          
          ## Progress Chart
          
          ```
          #{generate_ascii_chart}
          ```
          
          ## Trial Details
          
          | Trial | Score | Best | Duration | Parameters |
          |-------|-------|------|----------|------------|
        MD
        
        @trials.each do |trial|
          score_str = trial[:score]&.round(4) || 'Failed'
          best_str = trial[:best_score]&.round(4) || 'N/A'
          duration_str = trial[:duration_ms] ? "#{trial[:duration_ms]}ms" : 'N/A'
          params_str = trial[:parameters] ? format_parameters(trial[:parameters]) : 'N/A'
          
          report += "| #{trial[:trial_number]} | #{score_str} | #{best_str} | #{duration_str} | #{params_str} |\n"
        end
        
        report += "\n## Analysis\n\n"
        report += generate_analysis
        
        report
      end
      
      def success_rate
        return 0.0 if @trials.empty?
        successful = @trials.count { |t| t[:score] }
        (successful.to_f / @trials.length) * 100.0
      end
      
      def generate_ascii_chart
        return "No data to chart" if @trials.empty?
        
        scores = @trials.map { |t| t[:score] }.compact
        return "No successful trials to chart" if scores.empty?
        
        # Simple ASCII chart showing score progression
        max_score = scores.max
        min_score = scores.min
        range = max_score - min_score
        
        chart_lines = []
        chart_lines << "Score progression (#{scores.length} trials):"
        chart_lines << ""
        
        # Scale to 20 character width
        width = 20
        scores.each_with_index do |score, i|
          if range > 0
            normalized = ((score - min_score) / range) * width
            bar = '█' * normalized.to_i + '░' * (width - normalized.to_i)
          else
            bar = '█' * width
          end
          chart_lines << "#{sprintf('%2d', i+1)}: #{bar} #{score.round(4)}"
        end
        
        chart_lines << ""
        chart_lines << "Range: #{min_score.round(4)} - #{max_score.round(4)}"
        
        chart_lines.join("\n")
      end
      
      def format_parameters(params)
        return 'N/A' unless params.is_a?(Hash)
        
        # Show only first few key parameters to keep table readable
        key_params = params.slice(*%w[temperature max_tokens top_p model])
        if key_params.empty?
          key_params = params.first(2).to_h
        end
        
        key_params.map { |k, v| "#{k}=#{v}" }.join(', ')
      end
      
      def generate_analysis
        return "Not enough data for analysis." if @trials.length < 3
        
        analysis = []
        
        # Score trend analysis
        recent_trials = @trials.last(5)
        recent_scores = recent_trials.map { |t| t[:score] }.compact
        
        if recent_scores.length >= 3
          trend = if recent_scores[-1] > recent_scores[0]
            "improving"
          elsif recent_scores[-1] < recent_scores[0]
            "declining"
          else
            "stable"
          end
          analysis << "**Recent trend**: The optimization appears to be #{trend} in recent trials."
        end
        
        # Best parameters analysis
        best_trial = @trials.select { |t| t[:score] }.max_by { |t| t[:score] }
        if best_trial && best_trial[:parameters]
          analysis << "**Best configuration**: Trial #{best_trial[:trial_number]} achieved the best score with: #{format_parameters(best_trial[:parameters])}"
        end
        
        analysis.join("\n\n")
      end
    end
    
    # Predict module that integrates with token budget
    class PredictWithTokenBudget < DSPy::Predict
      attr_reader :token_budget
      
      def initialize(signature, budget_limit: 10000, **kwargs)
        super(signature, **kwargs)
        @token_budget = TokenBudgetSubscriber.new(budget_limit: budget_limit)
      end
      
      def forward(**inputs)
        if @token_budget.budget_exceeded?
          raise DSPy::TokenBudgetExceededError, 
                "Token budget exceeded: #{@token_budget.total_tokens}/#{@token_budget.budget_limit}"
        end
        
        result = super(**inputs)
        
        # Log current budget status after prediction
        if @token_budget.budget_remaining && @token_budget.budget_remaining < 1000
          DSPy.event('token_budget.warning', @token_budget.usage_summary)
        end
        
        result
      end
      
      def usage_summary
        @token_budget.usage_summary
      end
      
      def reset_budget
        @token_budget.reset_stats
      end
    end
  end
  
  # Exception for token budget exceeded
  class TokenBudgetExceededError < StandardError; end
end