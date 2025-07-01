# Multi-stage Pipelines

Advanced pipeline patterns for building sophisticated DSPy applications that require complex processing workflows, conditional logic, and sophisticated error handling.

## Pipeline Architecture

### Sequential Pipelines

```ruby
class DocumentProcessingPipeline < DSPy::Module
  def initialize
    @extractor = DSPy::Predict.new(ExtractDocumentInfo)
    @classifier = DSPy::ChainOfThought.new(ClassifyDocument)
    @analyzer = DSPy::Predict.new(AnalyzeContent)
    @summarizer = DSPy::ChainOfThought.new(GenerateSummary)
  end
  
  def call(document)
    # Stage 1: Extract basic information
    extraction = @extractor.call(text: document)
    
    # Stage 2: Classify document type (with reasoning)
    classification = @classifier.call(
      text: document,
      extracted_info: extraction.to_h
    )
    
    # Stage 3: Analyze content based on classification
    analysis = @analyzer.call(
      text: document,
      document_type: classification.type,
      context: build_analysis_context(extraction, classification)
    )
    
    # Stage 4: Generate summary with all context
    summary = @summarizer.call(
      text: document,
      analysis: analysis.insights,
      document_type: classification.type
    )
    
    DocumentProcessingResult.new(
      extraction: extraction,
      classification: classification,
      analysis: analysis,
      summary: summary,
      pipeline_metadata: capture_pipeline_metadata
    )
  end
end
```

### Parallel Pipelines

```ruby
class ParallelAnalysisPipeline < DSPy::Module
  def initialize
    @sentiment_analyzer = DSPy::Predict.new(AnalyzeSentiment)
    @topic_extractor = DSPy::Predict.new(ExtractTopics)
    @entity_recognizer = DSPy::Predict.new(RecognizeEntities)
    @language_detector = DSPy::Predict.new(DetectLanguage)
    @quality_assessor = DSPy::ChainOfThought.new(AssessQuality)
  end
  
  def call(text)
    # Run independent analyses in parallel
    Async do |task|
      sentiment_task = task.async { @sentiment_analyzer.call(text: text) }
      topics_task = task.async { @topic_extractor.call(text: text) }
      entities_task = task.async { @entity_recognizer.call(text: text) }
      language_task = task.async { @language_detector.call(text: text) }
      
      # Wait for all parallel tasks
      sentiment = sentiment_task.wait
      topics = topics_task.wait
      entities = entities_task.wait
      language = language_task.wait
      
      # Use parallel results for final quality assessment
      quality = @quality_assessor.call(
        text: text,
        sentiment: sentiment.sentiment,
        topics: topics.topics,
        entities: entities.entities,
        language: language.language
      )
      
      ParallelAnalysisResult.new(
        sentiment: sentiment,
        topics: topics,
        entities: entities,
        language: language,
        quality: quality,
        processing_time: calculate_parallel_time
      )
    end
  end
end
```

## Conditional Pipeline Logic

### Dynamic Routing

```ruby
class AdaptiveProcessingPipeline < DSPy::Module
  def initialize
    @complexity_assessor = DSPy::Predict.new(AssessComplexity)
    @simple_processor = DSPy::Predict.new(SimpleProcessing)
    @complex_processor = DSPy::ChainOfThought.new(ComplexProcessing)
    @expert_processor = DSPy::React.new(ExpertProcessing, tools: [ResearchTool.new])
  end
  
  def call(input)
    # Assess complexity first
    complexity = @complexity_assessor.call(text: input)
    
    # Route based on complexity
    processor = select_processor(complexity.level)
    
    # Add complexity context to processing
    result = processor.call(
      text: input,
      complexity_level: complexity.level,
      complexity_reasoning: complexity.reasoning
    )
    
    # Post-process based on complexity
    enhanced_result = enhance_result(result, complexity)
    
    AdaptiveProcessingResult.new(
      result: enhanced_result,
      complexity_assessment: complexity,
      processor_used: processor.class.name,
      confidence: calculate_confidence(result, complexity)
    )
  end
  
  private
  
  def select_processor(complexity_level)
    case complexity_level
    when ComplexityLevel::Low
      @simple_processor
    when ComplexityLevel::Medium
      @complex_processor
    when ComplexityLevel::High
      @expert_processor
    else
      @simple_processor  # Default fallback
    end
  end
end
```

### Multi-path Processing

```ruby
class MultiPathPipeline < DSPy::Module
  def initialize
    @initial_analyzer = DSPy::Predict.new(InitialAnalysis)
    
    # Different processing paths
    @technical_path = TechnicalProcessingPath.new
    @business_path = BusinessProcessingPath.new
    @creative_path = CreativeProcessingPath.new
    
    @path_merger = DSPy::ChainOfThought.new(MergePaths)
  end
  
  def call(input)
    # Initial analysis to determine paths
    initial = @initial_analyzer.call(text: input)
    
    # Determine which paths to execute
    paths_to_execute = select_paths(initial.characteristics)
    
    # Execute selected paths in parallel
    path_results = Async do |task|
      paths_to_execute.map do |path_name|
        task.async do
          path_processor = instance_variable_get("@#{path_name}_path")
          {
            path: path_name,
            result: path_processor.call(input, context: initial)
          }
        end
      end.map(&:wait)
    end
    
    # Merge results from all paths
    merged = @path_merger.call(
      input: input,
      initial_analysis: initial,
      path_results: path_results
    )
    
    MultiPathResult.new(
      initial_analysis: initial,
      paths_executed: paths_to_execute,
      path_results: path_results,
      merged_result: merged
    )
  end
  
  private
  
  def select_paths(characteristics)
    paths = []
    
    paths << :technical if characteristics.include?('technical_content')
    paths << :business if characteristics.include?('business_context')
    paths << :creative if characteristics.include?('creative_elements')
    
    # Always include at least one path
    paths << :technical if paths.empty?
    
    paths
  end
end
```

## Error Handling and Recovery

### Graceful Degradation

```ruby
class ResilientPipeline < DSPy::Module
  def initialize
    @primary_processors = build_primary_processors
    @fallback_processors = build_fallback_processors
    @error_handler = ErrorHandler.new
  end
  
  def call(input)
    results = {}
    errors = {}
    
    @primary_processors.each do |stage_name, processor|
      begin
        results[stage_name] = execute_with_timeout(processor, input, timeout: 30.seconds)
      rescue StandardError => e
        errors[stage_name] = e
        
        # Try fallback processor
        if fallback = @fallback_processors[stage_name]
          begin
            results[stage_name] = execute_with_timeout(fallback, input, timeout: 15.seconds)
            results["#{stage_name}_fallback_used"] = true
          rescue StandardError => fallback_error
            errors["#{stage_name}_fallback"] = fallback_error
            
            # Use cached or default result if available
            results[stage_name] = get_cached_or_default_result(stage_name, input)
          end
        end
      end
    end
    
    # Handle partial failures
    final_result = handle_partial_failures(results, errors, input)
    
    ResilientPipelineResult.new(
      results: results,
      errors: errors,
      success_rate: calculate_success_rate(results, errors),
      fallbacks_used: count_fallbacks_used(results),
      final_result: final_result
    )
  end
  
  private
  
  def execute_with_timeout(processor, input, timeout:)
    Timeout.timeout(timeout) do
      processor.call(input)
    end
  rescue Timeout::Error
    raise DSPy::TimeoutError, "Processor #{processor.class} timed out after #{timeout} seconds"
  end
  
  def handle_partial_failures(results, errors, input)
    success_count = results.count { |k, v| !k.to_s.include?('_fallback_used') && v }
    total_stages = @primary_processors.size
    
    if success_count >= total_stages * 0.7  # 70% success threshold
      combine_successful_results(results)
    else
      emergency_fallback_processing(input, results, errors)
    end
  end
end
```

### Circuit Breaker Pattern

```ruby
class CircuitBreakerPipeline < DSPy::Module
  def initialize
    @processors = build_processors
    @circuit_breakers = build_circuit_breakers
  end
  
  def call(input)
    results = {}
    
    @processors.each do |stage_name, processor|
      circuit_breaker = @circuit_breakers[stage_name]
      
      begin
        if circuit_breaker.closed?
          results[stage_name] = circuit_breaker.call do
            processor.call(input)
          end
        else
          # Circuit is open, use cached result or skip
          results[stage_name] = circuit_breaker.fallback_result || 
                               skip_stage_with_warning(stage_name)
        end
      rescue CircuitBreaker::OpenError
        DSPy.logger.warn "Circuit breaker open for #{stage_name}, using fallback"
        results[stage_name] = handle_circuit_open(stage_name, input)
      end
    end
    
    CircuitBreakerResult.new(
      results: results,
      circuit_states: @circuit_breakers.transform_values(&:state)
    )
  end
  
  private
  
  def build_circuit_breakers
    @processors.keys.to_h do |stage_name|
      [stage_name, CircuitBreaker.new(
        failure_threshold: 5,
        timeout: 60.seconds,
        expected_exceptions: [DSPy::LMError, DSPy::TimeoutError]
      )]
    end
  end
end
```

## Data Flow Patterns

### Stream Processing

```ruby
class StreamProcessingPipeline < DSPy::Module
  def initialize(batch_size: 10, buffer_timeout: 5.seconds)
    @batch_size = batch_size
    @buffer_timeout = buffer_timeout
    @processor = DSPy::Predict.new(ProcessBatch)
    @buffer = []
    @last_flush = Time.current
  end
  
  def process_item(item)
    @buffer << item
    
    if should_flush?
      flush_buffer
    else
      # Return immediately for streaming
      nil
    end
  end
  
  def flush_buffer
    return [] if @buffer.empty?
    
    batch = @buffer.dup
    @buffer.clear
    @last_flush = Time.current
    
    # Process batch
    result = @processor.call(
      items: batch,
      batch_size: batch.size,
      processing_timestamp: Time.current
    )
    
    # Return individual results
    result.processed_items
  end
  
  def finalize
    # Process any remaining items
    flush_buffer
  end
  
  private
  
  def should_flush?
    @buffer.size >= @batch_size ||
    Time.current - @last_flush >= @buffer_timeout
  end
end
```

### Map-Reduce Pipelines

```ruby
class MapReducePipeline < DSPy::Module
  def initialize(chunk_size: 1000, reducer_type: :summary)
    @chunk_size = chunk_size
    @mapper = DSPy::Predict.new(MapOperation)
    @reducer = select_reducer(reducer_type)
  end
  
  def call(large_dataset)
    # Map phase: process chunks in parallel
    chunks = large_dataset.each_slice(@chunk_size).to_a
    
    mapped_results = Async do |task|
      chunks.map.with_index do |chunk, index|
        task.async do
          @mapper.call(
            data_chunk: chunk,
            chunk_index: index,
            total_chunks: chunks.size
          )
        end
      end.map(&:wait)
    end
    
    # Reduce phase: combine results
    final_result = @reducer.call(
      mapped_results: mapped_results,
      original_size: large_dataset.size,
      chunks_processed: chunks.size
    )
    
    MapReduceResult.new(
      original_size: large_dataset.size,
      chunks_processed: chunks.size,
      mapped_results: mapped_results,
      final_result: final_result,
      processing_stats: calculate_processing_stats(mapped_results)
    )
  end
  
  private
  
  def select_reducer(type)
    case type
    when :summary
      DSPy::ChainOfThought.new(SummarizeResults)
    when :aggregation
      DSPy::Predict.new(AggregateResults)
    when :synthesis
      DSPy::ChainOfThought.new(SynthesizeResults)
    else
      DSPy::Predict.new(CombineResults)
    end
  end
end
```

## Pipeline Optimization

### Caching Strategies

```ruby
class CachedPipeline < DSPy::Module
  def initialize(cache_store: Rails.cache)
    @processors = build_processors
    @cache = cache_store
    @cache_config = configure_caching
  end
  
  def call(input)
    cache_key = generate_pipeline_cache_key(input)
    
    # Check for complete pipeline cache
    if cached_result = @cache.read(cache_key)
      return cached_result.merge(cache_hit: :full)
    end
    
    results = {}
    
    @processors.each do |stage_name, processor|
      stage_cache_key = generate_stage_cache_key(stage_name, input, results)
      
      if @cache_config[stage_name][:enabled]
        cached_stage_result = @cache.read(stage_cache_key)
        
        if cached_stage_result
          results[stage_name] = cached_stage_result
          next
        end
      end
      
      # Execute stage
      stage_result = processor.call(build_stage_input(input, results))
      results[stage_name] = stage_result
      
      # Cache stage result
      if @cache_config[stage_name][:enabled]
        @cache.write(
          stage_cache_key,
          stage_result,
          expires_in: @cache_config[stage_name][:ttl]
        )
      end
    end
    
    final_result = combine_stage_results(results)
    
    # Cache complete pipeline result
    @cache.write(cache_key, final_result, expires_in: 1.hour)
    
    final_result.merge(cache_hit: :none)
  end
  
  private
  
  def configure_caching
    {
      extraction: { enabled: true, ttl: 1.hour },
      classification: { enabled: true, ttl: 30.minutes },
      analysis: { enabled: false, ttl: nil },  # Always fresh
      summary: { enabled: true, ttl: 15.minutes }
    }
  end
end
```

### Performance Monitoring

```ruby
class MonitoredPipeline < DSPy::Module
  def initialize
    @processors = build_processors
    @performance_tracker = PerformanceTracker.new
    @bottleneck_detector = BottleneckDetector.new
  end
  
  def call(input)
    pipeline_start = Time.current
    stage_timings = {}
    results = {}
    
    @processors.each do |stage_name, processor|
      stage_start = Time.current
      
      # Execute stage with monitoring
      results[stage_name] = @performance_tracker.track_stage(stage_name) do
        processor.call(build_stage_input(input, results))
      end
      
      stage_duration = Time.current - stage_start
      stage_timings[stage_name] = stage_duration
      
      # Check for bottlenecks
      if @bottleneck_detector.is_bottleneck?(stage_name, stage_duration)
        DSPy.logger.warn "Bottleneck detected in stage #{stage_name}: #{stage_duration}s"
      end
    end
    
    total_duration = Time.current - pipeline_start
    
    # Record performance metrics
    record_pipeline_performance(stage_timings, total_duration)
    
    MonitoredPipelineResult.new(
      results: combine_stage_results(results),
      performance: {
        total_duration: total_duration,
        stage_timings: stage_timings,
        bottlenecks: @bottleneck_detector.detected_bottlenecks,
        throughput: calculate_throughput(input, total_duration)
      }
    )
  end
  
  private
  
  def record_pipeline_performance(stage_timings, total_duration)
    DSPy.metrics.histogram('pipeline.total_duration').record(total_duration)
    
    stage_timings.each do |stage, duration|
      DSPy.metrics.histogram("pipeline.stage.#{stage}.duration").record(duration)
    end
    
    # Calculate stage percentages
    stage_timings.each do |stage, duration|
      percentage = (duration / total_duration) * 100
      DSPy.metrics.histogram("pipeline.stage.#{stage}.percentage").record(percentage)
    end
  end
end
```

## Testing Pipeline Components

### Unit Testing

```ruby
RSpec.describe DocumentProcessingPipeline do
  let(:pipeline) { described_class.new }
  
  describe "#call" do
    let(:sample_document) { "This is a sample document for testing." }
    
    it "processes document through all stages" do
      result = pipeline.call(sample_document)
      
      expect(result.extraction).to be_present
      expect(result.classification).to be_present
      expect(result.analysis).to be_present
      expect(result.summary).to be_present
    end
    
    it "maintains context between stages" do
      result = pipeline.call(sample_document)
      
      # Classification should use extraction context
      expect(result.classification.context).to include('extracted_info')
      
      # Analysis should use classification context
      expect(result.analysis.context).to include('document_type')
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Pipeline Integration" do
  let(:pipeline) { DocumentProcessingPipeline.new }
  
  it "handles real-world documents end-to-end" do
    document = File.read("spec/fixtures/sample_contract.pdf")
    
    result = pipeline.call(document)
    
    expect(result.classification.type).to eq('legal_document')
    expect(result.analysis.insights).to include('contract_terms')
    expect(result.summary.summary).to be_present
  end
  
  it "processes documents within acceptable time limits" do
    document = "A" * 10000  # 10KB document
    
    execution_time = Benchmark.realtime do
      pipeline.call(document)
    end
    
    expect(execution_time).to be < 10.0  # Should complete within 10 seconds
  end
end
```

### Load Testing

```ruby
RSpec.describe "Pipeline Performance" do
  let(:pipeline) { DocumentProcessingPipeline.new }
  
  it "handles concurrent requests efficiently" do
    documents = Array.new(20) { |i| "Document content #{i}" }
    
    results = Async do |task|
      documents.map do |doc|
        task.async { pipeline.call(doc) }
      end.map(&:wait)
    end
    
    expect(results.size).to eq(20)
    expect(results.all?(&:valid?)).to be true
  end
end
```

Multi-stage pipelines enable sophisticated processing workflows while maintaining modularity, testability, and performance. Use these patterns to build complex applications that can handle real-world data processing requirements.