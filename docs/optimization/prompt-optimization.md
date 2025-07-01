# Prompt Optimization

DSPy.rb treats prompts as first-class objects that can be manipulated, optimized, and versioned. This enables systematic prompt engineering and automatic optimization.

## Prompt Objects

### Basic Prompt Structure

```ruby
class DocumentAnalysisPrompt < DSPy::Prompt
  def initialize(style: :professional, domain: :general)
    @style = style
    @domain = domain
    super()
  end
  
  def system_message
    case @style
    when :professional
      "You are a professional document analyst with expertise in #{@domain} content."
    when :casual
      "You're helping someone understand a document about #{@domain}."
    when :academic
      "You are an academic researcher specializing in #{@domain} analysis."
    end
  end
  
  def instruction_template
    <<~INSTRUCTION
      Analyze the following document and provide insights based on your expertise.
      
      Consider these aspects:
      #{analysis_aspects.join("\n")}
      
      Document: {text}
      
      Provide your analysis in the following format:
      {output_format}
    INSTRUCTION
  end
  
  private
  
  def analysis_aspects
    case @domain
    when :legal
      ["- Legal implications", "- Compliance requirements", "- Risk factors"]
    when :technical
      ["- Technical accuracy", "- Implementation feasibility", "- Best practices"]
    when :business
      ["- Business impact", "- Market implications", "- Strategic considerations"]
    else
      ["- Key themes", "- Important details", "- Overall assessment"]
    end
  end
end

# Usage
prompt = DocumentAnalysisPrompt.new(style: :academic, domain: :legal)
legal_analyzer = DSPy::Predict.new(AnalyzeDocument, prompt: prompt)
```

### Dynamic Prompt Generation

```ruby
class AdaptivePrompt < DSPy::Prompt
  def initialize(signature, context: {})
    @signature = signature
    @context = context
    super()
  end
  
  def generate_prompt(inputs)
    base_prompt = build_base_prompt
    contextual_additions = build_contextual_additions(inputs)
    examples = select_relevant_examples(inputs)
    
    combine_prompt_elements(base_prompt, contextual_additions, examples)
  end
  
  private
  
  def build_base_prompt
    <<~PROMPT
      Task: #{@signature.description}
      
      Input Fields: #{format_input_fields}
      Output Fields: #{format_output_fields}
    PROMPT
  end
  
  def build_contextual_additions(inputs)
    additions = []
    
    # Add domain-specific context
    if domain = detect_domain(inputs)
      additions << "Domain Context: #{domain_context(domain)}"
    end
    
    # Add complexity guidance
    if complexity = assess_complexity(inputs)
      additions << "Complexity Level: #{complexity_guidance(complexity)}"
    end
    
    additions.join("\n\n")
  end
  
  def select_relevant_examples(inputs)
    # Select the most relevant examples based on input similarity
    candidate_examples = @context[:examples] || []
    
    return [] if candidate_examples.empty?
    
    similarity_scores = candidate_examples.map do |example|
      {
        example: example,
        similarity: calculate_similarity(inputs, example.inputs)
      }
    end
    
    # Return top 3 most similar examples
    similarity_scores.sort_by { |item| -item[:similarity] }
                    .first(3)
                    .map { |item| format_example(item[:example]) }
  end
end
```

## Prompt Templates

### Template System

```ruby
class PromptTemplate
  def initialize(template_string)
    @template = template_string
    @variables = extract_variables(template_string)
  end
  
  def render(variables = {})
    rendered = @template.dup
    
    @variables.each do |var|
      if variables.key?(var)
        rendered.gsub!("{#{var}}", variables[var].to_s)
      else
        raise DSPy::PromptError, "Missing variable: #{var}"
      end
    end
    
    rendered
  end
  
  def required_variables
    @variables
  end
  
  private
  
  def extract_variables(template)
    template.scan(/\{(\w+)\}/).flatten.uniq
  end
end

# Library of reusable templates
module PromptTemplates
  CLASSIFICATION = PromptTemplate.new(<<~TEMPLATE)
    You are an expert classifier for {domain} content.
    
    Task: Classify the following {content_type} into one of these categories: {categories}
    
    {content_type}: {input_text}
    
    Consider these factors when classifying:
    {classification_factors}
    
    Provide your classification with confidence level (0.0 to 1.0).
  TEMPLATE
  
  EXTRACTION = PromptTemplate.new(<<~TEMPLATE)
    Extract {entity_types} from the following text.
    
    Text: {input_text}
    
    For each {entity_type}, provide:
    - The exact text span
    - Confidence level (0.0 to 1.0)
    - Context (surrounding words)
    
    {additional_instructions}
  TEMPLATE
  
  REASONING = PromptTemplate.new(<<~TEMPLATE)
    You need to {task_description}.
    
    Think step by step:
    1. {step_1_description}
    2. {step_2_description}
    3. {step_3_description}
    
    Input: {input_data}
    
    Show your reasoning process clearly, then provide your final answer.
  TEMPLATE
end

# Usage
classification_prompt = PromptTemplates::CLASSIFICATION.render(
  domain: "sentiment analysis",
  content_type: "customer review",
  categories: "positive, negative, neutral",
  input_text: "This product is amazing!",
  classification_factors: "tone, specific words, overall message"
)
```

### Conditional Templates

```ruby
class ConditionalPromptTemplate
  def initialize
    @conditions = []
    @base_template = ""
  end
  
  def base(template)
    @base_template = template
    self
  end
  
  def when(condition, template_addition)
    @conditions << { condition: condition, template: template_addition }
    self
  end
  
  def render(context = {})
    rendered = @base_template.dup
    
    @conditions.each do |rule|
      if rule[:condition].call(context)
        rendered += "\n\n" + rule[:template]
      end
    end
    
    PromptTemplate.new(rendered).render(context)
  end
end

# Usage
adaptive_template = ConditionalPromptTemplate.new
  .base("Analyze the following text: {text}")
  .when(
    ->(ctx) { ctx[:complexity] == :high },
    "Take extra care with this complex text. Consider multiple interpretations."
  )
  .when(
    ->(ctx) { ctx[:domain] == :technical },
    "Pay attention to technical terminology and accuracy."
  )
  .when(
    ->(ctx) { ctx[:examples]&.any? },
    "Here are some examples to guide your analysis:\n{examples}"
  )

prompt = adaptive_template.render(
  text: "Complex technical document...",
  complexity: :high,
  domain: :technical,
  examples: ["Example 1", "Example 2"]
)
```

## Automatic Prompt Optimization

### Optimization Strategies

```ruby
class PromptOptimizer
  def initialize(signature, metric: :accuracy)
    @signature = signature
    @metric = metric
    @optimization_history = []
  end
  
  def optimize(examples, strategies: [:instruction_tuning, :example_selection, :format_optimization])
    best_prompt = nil
    best_score = 0.0
    
    strategies.each do |strategy|
      optimized_prompt = apply_strategy(strategy, examples)
      score = evaluate_prompt(optimized_prompt, examples)
      
      if score > best_score
        best_score = score
        best_prompt = optimized_prompt
      end
      
      @optimization_history << {
        strategy: strategy,
        prompt: optimized_prompt,
        score: score,
        timestamp: Time.current
      }
    end
    
    OptimizationResult.new(
      best_prompt: best_prompt,
      best_score: best_score,
      optimization_history: @optimization_history
    )
  end
  
  private
  
  def apply_strategy(strategy, examples)
    case strategy
    when :instruction_tuning
      optimize_instructions(examples)
    when :example_selection
      optimize_example_selection(examples)
    when :format_optimization
      optimize_output_format(examples)
    when :reasoning_enhancement
      add_reasoning_prompts(examples)
    end
  end
  
  def optimize_instructions(examples)
    # Try different instruction phrasings
    instruction_variants = generate_instruction_variants
    
    best_instruction = instruction_variants.max_by do |instruction|
      prompt = create_prompt_with_instruction(instruction)
      evaluate_prompt(prompt, examples.sample(5))  # Quick evaluation
    end
    
    create_prompt_with_instruction(best_instruction)
  end
  
  def optimize_example_selection(examples)
    # Find the most effective few-shot examples
    all_combinations = examples.combination(3).to_a  # Try combinations of 3
    
    best_combination = all_combinations.max_by do |example_set|
      prompt = create_prompt_with_examples(example_set)
      evaluate_prompt(prompt, examples - example_set)  # Test on remaining examples
    end
    
    create_prompt_with_examples(best_combination)
  end
  
  def optimize_output_format(examples)
    # Try different output formatting approaches
    format_variants = [
      :structured_json,
      :labeled_fields,
      :natural_language,
      :bullet_points
    ]
    
    best_format = format_variants.max_by do |format|
      prompt = create_prompt_with_format(format)
      evaluate_prompt(prompt, examples.sample(5))
    end
    
    create_prompt_with_format(best_format)
  end
end
```

### Evolutionary Optimization

```ruby
class EvolutionaryPromptOptimizer
  def initialize(signature, population_size: 20, generations: 10)
    @signature = signature
    @population_size = population_size
    @generations = generations
  end
  
  def optimize(examples)
    # Initialize population with random prompt variations
    population = generate_initial_population
    
    @generations.times do |generation|
      # Evaluate fitness of each prompt
      fitness_scores = population.map do |prompt|
        evaluate_fitness(prompt, examples)
      end
      
      # Select top performers
      elite = select_elite(population, fitness_scores)
      
      # Generate new population through crossover and mutation
      population = evolve_population(elite)
      
      log_generation_progress(generation, population, fitness_scores)
    end
    
    best_prompt = population.max_by { |prompt| evaluate_fitness(prompt, examples) }
    
    EvolutionaryResult.new(
      best_prompt: best_prompt,
      final_fitness: evaluate_fitness(best_prompt, examples),
      generations: @generations
    )
  end
  
  private
  
  def generate_initial_population
    @population_size.times.map do
      create_random_prompt_variant
    end
  end
  
  def create_random_prompt_variant
    # Generate random variations of:
    # - Instruction phrasing
    # - Example selection
    # - Output format
    # - Additional context
    
    RandomPromptGenerator.new(@signature).generate
  end
  
  def evolve_population(elite)
    new_population = elite.dup  # Keep elite
    
    while new_population.size < @population_size
      parent1, parent2 = elite.sample(2)
      
      # Crossover
      child = crossover_prompts(parent1, parent2)
      
      # Mutation
      child = mutate_prompt(child) if rand < 0.1
      
      new_population << child
    end
    
    new_population
  end
  
  def crossover_prompts(prompt1, prompt2)
    # Combine elements from two parent prompts
    PromptCrossover.new(prompt1, prompt2).generate_offspring
  end
  
  def mutate_prompt(prompt)
    # Apply small random changes to prompt
    PromptMutator.new(prompt).mutate
  end
end
```

## Prompt Versioning and Management

### Version Control System

```ruby
class PromptVersionControl
  def initialize(storage_path)
    @storage_path = storage_path
    @versions = {}
  end
  
  def save_prompt(prompt, version:, metadata: {})
    version_data = {
      version: version,
      prompt_class: prompt.class.name,
      prompt_data: prompt.serialize,
      metadata: metadata.merge(
        created_at: Time.current,
        performance_metrics: metadata[:performance_metrics] || {}
      ),
      checksum: calculate_checksum(prompt)
    }
    
    @versions[version] = version_data
    persist_version(version, version_data)
    
    version
  end
  
  def load_prompt(version)
    version_data = load_version(version)
    prompt_class = version_data[:prompt_class].constantize
    
    prompt_class.deserialize(version_data[:prompt_data])
  end
  
  def compare_versions(version1, version2)
    prompt1 = load_prompt(version1)
    prompt2 = load_prompt(version2)
    
    PromptComparator.new(prompt1, prompt2).compare
  end
  
  def get_best_performing_version(metric: :accuracy)
    versions_with_metrics = @versions.select do |version, data|
      data[:metadata][:performance_metrics].key?(metric)
    end
    
    best_version = versions_with_metrics.max_by do |version, data|
      data[:metadata][:performance_metrics][metric]
    end
    
    best_version&.first
  end
  
  private
  
  def persist_version(version, data)
    File.write("#{@storage_path}/prompt_v#{version}.json", data.to_json)
  end
  
  def load_version(version)
    JSON.parse(File.read("#{@storage_path}/prompt_v#{version}.json"), symbolize_names: true)
  end
end

# Usage
version_control = PromptVersionControl.new("prompts/")

# Save optimized prompt
version_control.save_prompt(
  optimized_prompt, 
  version: "1.2.0",
  metadata: {
    optimization_method: "evolutionary",
    performance_metrics: { accuracy: 0.92, latency: 1.2 },
    test_examples_count: 100
  }
)

# Load best performing prompt
best_prompt = version_control.load_prompt(
  version_control.get_best_performing_version(:accuracy)
)
```

### A/B Testing for Prompts

```ruby
class PromptABTester
  def initialize(control_prompt, treatment_prompt)
    @control_prompt = control_prompt
    @treatment_prompt = treatment_prompt
    @results = { control: [], treatment: [] }
  end
  
  def run_test(examples, allocation_ratio: 0.5)
    examples.shuffle.each_with_index do |example, index|
      # Allocate to control or treatment
      group = index.to_f / examples.size < allocation_ratio ? :control : :treatment
      
      prompt = group == :control ? @control_prompt : @treatment_prompt
      predictor = DSPy::Predict.new(@signature, prompt: prompt)
      
      result = predictor.call(example.inputs)
      
      @results[group] << {
        example: example,
        result: result,
        correct: result.matches_expected?(example.outputs),
        latency: measure_latency { predictor.call(example.inputs) }
      }
    end
    
    analyze_results
  end
  
  private
  
  def analyze_results
    control_metrics = calculate_metrics(@results[:control])
    treatment_metrics = calculate_metrics(@results[:treatment])
    
    statistical_significance = calculate_statistical_significance(
      @results[:control],
      @results[:treatment]
    )
    
    ABTestResult.new(
      control_metrics: control_metrics,
      treatment_metrics: treatment_metrics,
      statistical_significance: statistical_significance,
      recommendation: determine_recommendation(control_metrics, treatment_metrics)
    )
  end
  
  def calculate_metrics(results)
    total = results.size
    correct = results.count { |r| r[:correct] }
    avg_latency = results.map { |r| r[:latency] }.sum / total
    
    {
      accuracy: correct.to_f / total,
      average_latency: avg_latency,
      sample_size: total
    }
  end
  
  def determine_recommendation(control, treatment)
    accuracy_improvement = treatment[:accuracy] - control[:accuracy]
    latency_change = treatment[:average_latency] - control[:average_latency]
    
    if accuracy_improvement > 0.02 && latency_change < 0.5
      :use_treatment
    elsif accuracy_improvement < -0.01 || latency_change > 2.0
      :use_control
    else
      :inconclusive
    end
  end
end
```

## Prompt Analytics

### Performance Tracking

```ruby
class PromptAnalytics
  def initialize
    @performance_data = []
    @error_patterns = Hash.new(0)
  end
  
  def track_performance(prompt, inputs, outputs, metadata = {})
    performance_record = {
      prompt_hash: calculate_prompt_hash(prompt),
      timestamp: Time.current,
      inputs: inputs,
      outputs: outputs,
      success: metadata[:success] || true,
      latency: metadata[:latency],
      token_usage: metadata[:token_usage],
      cost: metadata[:cost]
    }
    
    @performance_data << performance_record
    
    if !performance_record[:success] && metadata[:error]
      track_error_pattern(metadata[:error])
    end
  end
  
  def generate_report(time_period: 24.hours)
    cutoff_time = Time.current - time_period
    recent_data = @performance_data.select { |record| record[:timestamp] > cutoff_time }
    
    {
      total_requests: recent_data.size,
      success_rate: calculate_success_rate(recent_data),
      average_latency: calculate_average_latency(recent_data),
      total_cost: calculate_total_cost(recent_data),
      error_patterns: @error_patterns.sort_by { |pattern, count| -count }.first(5),
      performance_trend: calculate_performance_trend(recent_data)
    }
  end
  
  def identify_optimization_opportunities(threshold: 0.1)
    opportunities = []
    
    # High latency prompts
    high_latency = @performance_data.select { |record| record[:latency] > 3.0 }
    if high_latency.size.to_f / @performance_data.size > threshold
      opportunities << {
        type: :latency_optimization,
        description: "#{high_latency.size} requests exceeded 3s latency",
        recommendation: "Consider shorter prompts or faster models"
      }
    end
    
    # High error rate
    error_rate = 1.0 - calculate_success_rate(@performance_data)
    if error_rate > threshold
      opportunities << {
        type: :error_reduction,
        description: "Error rate of #{(error_rate * 100).round(1)}%",
        recommendation: "Review and optimize prompt for common error patterns"
      }
    end
    
    opportunities
  end
  
  private
  
  def track_error_pattern(error)
    error_key = "#{error.class.name}: #{error.message.truncate(100)}"
    @error_patterns[error_key] += 1
  end
end
```

## Best Practices

### 1. Iterative Improvement

```ruby
class PromptImprovementCycle
  def initialize(signature, examples)
    @signature = signature
    @examples = examples
    @current_prompt = nil
    @improvement_history = []
  end
  
  def run_improvement_cycle
    # 1. Baseline measurement
    baseline_performance = measure_baseline
    
    # 2. Generate variations
    variations = generate_prompt_variations
    
    # 3. Test variations
    variation_results = test_variations(variations)
    
    # 4. Select best performer
    best_variation = select_best_variation(variation_results)
    
    # 5. A/B test against current
    if @current_prompt
      ab_result = run_ab_test(@current_prompt, best_variation)
      @current_prompt = ab_result.recommended_prompt
    else
      @current_prompt = best_variation
    end
    
    # 6. Record improvement
    @improvement_history << {
      cycle: @improvement_history.size + 1,
      baseline: baseline_performance,
      improvement: measure_current_performance - baseline_performance,
      timestamp: Time.current
    }
    
    @current_prompt
  end
end
```

### 2. Domain-Specific Optimization

```ruby
class DomainSpecificOptimizer
  def initialize(domain)
    @domain = domain
    @domain_knowledge = load_domain_knowledge(domain)
  end
  
  def optimize_for_domain(base_prompt)
    # Add domain-specific instructions
    domain_enhanced = add_domain_context(base_prompt)
    
    # Include domain-specific examples
    domain_examples = select_domain_examples
    
    # Use domain-specific evaluation metrics
    domain_metrics = get_domain_metrics
    
    optimize_with_domain_knowledge(domain_enhanced, domain_examples, domain_metrics)
  end
  
  private
  
  def load_domain_knowledge(domain)
    {
      medical: {
        terminology: load_medical_terms,
        guidelines: load_medical_guidelines,
        regulatory_requirements: load_medical_regulations
      },
      legal: {
        terminology: load_legal_terms,
        precedents: load_legal_precedents,
        jurisdictional_requirements: load_jurisdictional_rules
      },
      financial: {
        terminology: load_financial_terms,
        regulations: load_financial_regulations,
        market_context: load_market_data
      }
    }[domain] || {}
  end
end
```

### 3. Continuous Monitoring

```ruby
class PromptMonitor
  def initialize(prompt, alert_thresholds: {})
    @prompt = prompt
    @alert_thresholds = {
      accuracy_drop: 0.05,
      latency_increase: 2.0,
      error_rate: 0.1
    }.merge(alert_thresholds)
    
    @baseline_metrics = establish_baseline
  end
  
  def monitor_performance(current_metrics)
    alerts = []
    
    # Check for accuracy drops
    if accuracy_dropped?(current_metrics)
      alerts << create_alert(:accuracy_drop, current_metrics)
    end
    
    # Check for latency increases
    if latency_increased?(current_metrics)
      alerts << create_alert(:latency_increase, current_metrics)
    end
    
    # Check for error rate spikes
    if error_rate_high?(current_metrics)
      alerts << create_alert(:error_spike, current_metrics)
    end
    
    send_alerts(alerts) unless alerts.empty?
    alerts
  end
  
  private
  
  def send_alerts(alerts)
    alerts.each do |alert|
      DSPy.logger.warn "Prompt performance alert: #{alert[:message]}"
      
      # Send to monitoring system
      DSPy.instrumentation.record_alert(alert)
    end
  end
end
```

Prompt optimization is an ongoing process that requires systematic measurement, experimentation, and iteration. Use the tools and patterns provided to continuously improve your prompt performance and reliability.