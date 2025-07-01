# Modules & Pipelines

Modules enable you to compose multiple predictors into sophisticated, reusable workflows. They're the building blocks for complex LLM applications that require multiple processing steps.

## Basic Module Structure

```ruby
class DocumentProcessor < DSPy::Module
  def initialize
    @classifier = DSPy::Predict.new(ClassifyDocument)
    @summarizer = DSPy::ChainOfThought.new(SummarizeDocument)
    @extractor = DSPy::Predict.new(ExtractKeyInfo)
  end
  
  def call(document)
    # Process document through multiple stages
    classification = @classifier.call(text: document)
    summary = @summarizer.call(text: document, context: classification.category)
    key_info = @extractor.call(text: summary.summary)
    
    {
      classification: classification,
      summary: summary.summary,
      key_information: key_info,
      processed_at: Time.current
    }
  end
end
```

## Sequential Processing Modules

### Linear Pipeline

```ruby
class ContentAnalysisPipeline < DSPy::Module
  def initialize
    @language_detector = DSPy::Predict.new(DetectLanguage)
    @translator = DSPy::Predict.new(TranslateText)
    @sentiment_analyzer = DSPy::ChainOfThought.new(AnalyzeSentiment)
    @topic_extractor = DSPy::Predict.new(ExtractTopics)
  end
  
  def call(text, target_language: 'en')
    # Step 1: Detect language
    language_result = @language_detector.call(text: text)
    
    # Step 2: Translate if needed
    processed_text = if language_result.language != target_language
      translation = @translator.call(
        text: text,
        source_language: language_result.language,
        target_language: target_language
      )
      translation.translated_text
    else
      text
    end
    
    # Step 3: Analyze sentiment with reasoning
    sentiment = @sentiment_analyzer.call(text: processed_text)
    
    # Step 4: Extract topics
    topics = @topic_extractor.call(text: processed_text)
    
    ContentAnalysisResult.new(
      original_text: text,
      original_language: language_result.language,
      processed_text: processed_text,
      sentiment: sentiment,
      topics: topics.topics,
      processing_pipeline: self.class.name
    )
  end
end
```

### Multi-Stage with Context Passing

```ruby
class ResearchPipeline < DSPy::Module
  def initialize
    @query_analyzer = DSPy::ChainOfThought.new(AnalyzeQuery)
    @searcher = DSPy::React.new(SearchAndGather, tools: [WebSearchTool.new])
    @synthesizer = DSPy::ChainOfThought.new(SynthesizeFindings)
    @fact_checker = DSPy::Predict.new(FactCheck)
  end
  
  def call(research_question)
    context = ResearchContext.new
    
    # Stage 1: Analyze the research question
    analysis = @query_analyzer.call(query: research_question)
    context.add_stage(:analysis, analysis)
    
    # Stage 2: Search and gather information
    search_results = @searcher.call(
      query: research_question,
      search_strategy: analysis.recommended_strategy,
      depth: analysis.complexity_level
    )
    context.add_stage(:search, search_results)
    
    # Stage 3: Synthesize findings
    synthesis = @synthesizer.call(
      question: research_question,
      sources: search_results.sources,
      context: context.summary
    )
    context.add_stage(:synthesis, synthesis)
    
    # Stage 4: Fact-check the synthesis
    fact_check = @fact_checker.call(
      claims: synthesis.key_claims,
      sources: search_results.sources
    )
    context.add_stage(:fact_check, fact_check)
    
    ResearchResult.new(
      question: research_question,
      answer: synthesis.answer,
      confidence: fact_check.overall_confidence,
      sources: search_results.sources,
      context: context,
      reasoning_trace: synthesis.reasoning
    )
  end
end

class ResearchContext
  def initialize
    @stages = {}
    @metadata = { created_at: Time.current }
  end
  
  def add_stage(name, result)
    @stages[name] = {
      result: result,
      completed_at: Time.current
    }
  end
  
  def summary
    @stages.map { |name, stage| "#{name}: #{stage[:result].summary}" }.join("\n")
  end
end
```

## Conditional Processing Modules

### Dynamic Routing

```ruby
class SmartDocumentProcessor < DSPy::Module
  def initialize
    @document_classifier = DSPy::Predict.new(ClassifyDocumentType)
    @email_processor = EmailProcessor.new
    @legal_processor = LegalDocumentProcessor.new
    @technical_processor = TechnicalDocumentProcessor.new
    @general_processor = GeneralDocumentProcessor.new
  end
  
  def call(document)
    # Determine document type
    classification = @document_classifier.call(text: document)
    
    # Route to appropriate specialized processor
    processor = case classification.document_type
    when DocumentType::Email
      @email_processor
    when DocumentType::Legal
      @legal_processor
    when DocumentType::Technical
      @technical_processor
    else
      @general_processor
    end
    
    # Process with specialized logic
    result = processor.call(document)
    
    # Add routing metadata
    result.merge(
      document_type: classification.document_type,
      processor_used: processor.class.name,
      routing_confidence: classification.confidence
    )
  end
end
```

### Adaptive Processing

```ruby
class AdaptiveAnalyzer < DSPy::Module
  def initialize
    @complexity_assessor = DSPy::Predict.new(AssessComplexity)
    @simple_analyzer = DSPy::Predict.new(SimpleAnalysis)
    @complex_analyzer = DSPy::ChainOfThought.new(ComplexAnalysis)
    @expert_analyzer = DSPy::React.new(ExpertAnalysis, tools: [ResearchTool.new])
  end
  
  def call(text)
    # Assess complexity first
    complexity = @complexity_assessor.call(text: text)
    
    # Choose analysis depth based on complexity
    analyzer = case complexity.level
    when ComplexityLevel::Low
      @simple_analyzer
    when ComplexityLevel::Medium
      @complex_analyzer
    when ComplexityLevel::High
      @expert_analyzer
    end
    
    # Perform analysis
    result = analyzer.call(text: text)
    
    # Add adaptive metadata
    result.merge(
      complexity_assessment: complexity,
      analysis_method: analyzer.class.name,
      processing_time: measure_processing_time { result }
    )
  end
end
```

## Parallel Processing Modules

### Concurrent Analysis

```ruby
class ParallelContentAnalyzer < DSPy::Module
  def initialize
    @sentiment_analyzer = DSPy::Predict.new(AnalyzeSentiment)
    @topic_extractor = DSPy::Predict.new(ExtractTopics)
    @entity_extractor = DSPy::Predict.new(ExtractEntities)
    @language_detector = DSPy::Predict.new(DetectLanguage)
  end
  
  def call(text)
    # Run multiple analyses in parallel
    Async do |task|
      sentiment_task = task.async { @sentiment_analyzer.call(text: text) }
      topics_task = task.async { @topic_extractor.call(text: text) }
      entities_task = task.async { @entity_extractor.call(text: text) }
      language_task = task.async { @language_detector.call(text: text) }
      
      # Wait for all to complete
      sentiment = sentiment_task.wait
      topics = topics_task.wait
      entities = entities_task.wait
      language = language_task.wait
      
      ContentAnalysisResult.new(
        text: text,
        sentiment: sentiment,
        topics: topics.topics,
        entities: entities.entities,
        language: language.language,
        confidence: calculate_overall_confidence(sentiment, topics, entities),
        processing_method: :parallel
      )
    end
  end
end
```

### Map-Reduce Pattern

```ruby
class LargeDocumentProcessor < DSPy::Module
  def initialize(chunk_size: 1000)
    @chunk_size = chunk_size
    @chunk_processor = DSPy::ChainOfThought.new(ProcessChunk)
    @aggregator = DSPy::ChainOfThought.new(AggregateResults)
  end
  
  def call(large_document)
    # Split document into manageable chunks
    chunks = split_into_chunks(large_document, @chunk_size)
    
    # Process chunks in parallel (Map phase)
    chunk_results = Async do |task|
      chunks.map.with_index do |chunk, index|
        task.async do
          @chunk_processor.call(
            text: chunk,
            chunk_index: index,
            total_chunks: chunks.size
          )
        end
      end.map(&:wait)
    end
    
    # Aggregate results (Reduce phase)
    final_result = @aggregator.call(
      chunk_results: chunk_results,
      original_document_length: large_document.length,
      processing_metadata: {
        chunks_processed: chunks.size,
        avg_chunk_size: chunks.map(&:length).sum / chunks.size
      }
    )
    
    final_result
  end
  
  private
  
  def split_into_chunks(text, size)
    # Smart chunking that respects sentence boundaries
    sentences = text.split(/[.!?]+/)
    chunks = []
    current_chunk = ""
    
    sentences.each do |sentence|
      if current_chunk.length + sentence.length <= size
        current_chunk += sentence + ". "
      else
        chunks << current_chunk.strip
        current_chunk = sentence + ". "
      end
    end
    
    chunks << current_chunk.strip unless current_chunk.empty?
    chunks
  end
end
```

## Error Handling in Modules

### Graceful Degradation

```ruby
class RobustProcessingModule < DSPy::Module
  def initialize
    @primary_processors = build_primary_processors
    @fallback_processors = build_fallback_processors
  end
  
  def call(input)
    results = {}
    errors = {}
    
    @primary_processors.each do |name, processor|
      begin
        results[name] = processor.call(input)
      rescue StandardError => e
        errors[name] = e
        
        # Try fallback processor
        if fallback = @fallback_processors[name]
          begin
            results[name] = fallback.call(input)
            results["#{name}_fallback_used"] = true
          rescue StandardError => fallback_error
            errors["#{name}_fallback"] = fallback_error
          end
        end
      end
    end
    
    ProcessingResult.new(
      input: input,
      results: results,
      errors: errors,
      success_rate: results.size.to_f / @primary_processors.size,
      fallbacks_used: results.count { |k, v| k.to_s.include?('_fallback_used') }
    )
  end
end
```

### Retry Logic

```ruby
class RetryableModule < DSPy::Module
  def initialize(max_retries: 3, backoff: 1.0)
    @processor = build_processor
    @max_retries = max_retries
    @backoff = backoff
  end
  
  def call(input)
    retries = 0
    
    begin
      @processor.call(input)
    rescue DSPy::LMError, DSPy::TimeoutError => e
      retries += 1
      
      if retries <= @max_retries
        sleep(@backoff * retries)  # Exponential backoff
        retry
      else
        raise DSPy::ProcessingError, "Failed after #{@max_retries} retries: #{e.message}"
      end
    end
  end
end
```

## Module Composition

### Nested Modules

```ruby
class ComprehensiveAnalysisModule < DSPy::Module
  def initialize
    @content_processor = ContentAnalysisPipeline.new
    @research_module = ResearchPipeline.new
    @fact_checker = FactCheckingModule.new
    @report_generator = ReportGenerationModule.new
  end
  
  def call(topic, source_documents)
    # Stage 1: Process all source documents
    processed_docs = source_documents.map do |doc|
      @content_processor.call(doc)
    end
    
    # Stage 2: Research additional information
    research = @research_module.call("Comprehensive analysis of #{topic}")
    
    # Stage 3: Fact-check all findings
    fact_check = @fact_checker.call(
      claims: extract_claims(processed_docs, research),
      sources: source_documents + research.sources
    )
    
    # Stage 4: Generate final report
    @report_generator.call(
      topic: topic,
      processed_documents: processed_docs,
      research_findings: research,
      fact_check_results: fact_check
    )
  end
end
```

### Modular Plugin System

```ruby
class PluggableAnalysisModule < DSPy::Module
  def initialize(plugins: [])
    @core_processor = CoreProcessor.new
    @plugins = plugins
  end
  
  def call(input)
    # Start with core processing
    result = @core_processor.call(input)
    
    # Apply each plugin in sequence
    @plugins.reduce(result) do |current_result, plugin|
      plugin.process(current_result, input)
    end
  end
  
  def add_plugin(plugin)
    @plugins << plugin
  end
  
  def remove_plugin(plugin_class)
    @plugins.reject! { |p| p.is_a?(plugin_class) }
  end
end

# Plugin example
class SentimentPlugin
  def process(result, original_input)
    sentiment = DSPy::Predict.new(AnalyzeSentiment).call(text: original_input)
    result.merge(sentiment_analysis: sentiment)
  end
end

# Usage
analyzer = PluggableAnalysisModule.new(plugins: [
  SentimentPlugin.new,
  TopicExtractionPlugin.new,
  EntityRecognitionPlugin.new
])
```

## Testing Modules

### Unit Testing

```ruby
RSpec.describe DocumentProcessor do
  let(:processor) { described_class.new }
  
  describe "#call" do
    let(:sample_document) { "This is a sample document for testing." }
    
    it "processes document through all stages" do
      result = processor.call(sample_document)
      
      expect(result).to include(:classification, :summary, :key_information)
      expect(result[:processed_at]).to be_within(1.second).of(Time.current)
    end
    
    it "handles empty documents gracefully" do
      result = processor.call("")
      
      expect(result).to be_a(Hash)
      expect(result[:classification]).to be_present
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Module Integration" do
  let(:pipeline) { ContentAnalysisPipeline.new }
  
  it "processes real content end-to-end" do
    content = File.read("spec/fixtures/sample_article.txt")
    
    result = pipeline.call(content, target_language: 'en')
    
    expect(result.sentiment).to be_present
    expect(result.topics).to be_an(Array)
    expect(result.topics).not_to be_empty
    expect(result.processing_pipeline).to eq('ContentAnalysisPipeline')
  end
end
```

### Performance Testing

```ruby
RSpec.describe "Module Performance" do
  let(:processor) { ParallelContentAnalyzer.new }
  
  it "processes content within acceptable time limits" do
    content = "A" * 1000  # 1KB of content
    
    execution_time = Benchmark.realtime do
      processor.call(content)
    end
    
    expect(execution_time).to be < 5.0  # Should complete within 5 seconds
  end
  
  it "handles concurrent requests efficiently" do
    requests = Array.new(10) { "Content for request #{_1}" }
    
    execution_time = Benchmark.realtime do
      Async do |task|
        requests.map { |content| task.async { processor.call(content) } }
               .map(&:wait)
      end
    end
    
    expect(execution_time).to be < 10.0  # All requests within 10 seconds
  end
end
```

## Best Practices

### 1. Clear Stage Separation

```ruby
class WellStructuredModule < DSPy::Module
  def call(input)
    # Stage 1: Input validation and preprocessing
    validated_input = validate_and_preprocess(input)
    
    # Stage 2: Core processing
    core_result = process_core_logic(validated_input)
    
    # Stage 3: Post-processing and enrichment
    enriched_result = enrich_result(core_result)
    
    # Stage 4: Output formatting
    format_output(enriched_result)
  end
end
```

### 2. Context Preservation

```ruby
class ContextAwareModule < DSPy::Module
  def call(input, context: {})
    processing_context = build_context(input, context)
    
    stages.reduce(processing_context) do |ctx, stage|
      stage_result = stage.call(ctx.current_input)
      ctx.add_stage_result(stage.name, stage_result)
      ctx
    end.final_result
  end
end
```

### 3. Resource Management

```ruby
class ResourceManagedModule < DSPy::Module
  def call(input)
    acquire_resources
    
    begin
      process_input(input)
    ensure
      release_resources
    end
  end
  
  private
  
  def acquire_resources
    @database_connection = acquire_db_connection
    @cache_connection = acquire_cache_connection
  end
  
  def release_resources
    @database_connection&.close
    @cache_connection&.close
  end
end
```

### 4. Monitoring and Observability

```ruby
class InstrumentedModule < DSPy::Module
  def call(input)
    start_time = Time.current
    stage_times = {}
    
    begin
      result = with_instrumentation(stage_times) do
        process_stages(input)
      end
      
      record_success_metrics(start_time, stage_times, result)
      result
    rescue StandardError => e
      record_error_metrics(start_time, stage_times, e)
      raise
    end
  end
  
  private
  
  def with_instrumentation(stage_times)
    # Track timing for each stage
    # Log intermediate results
    # Monitor resource usage
  end
end
```

Modules are the key to building complex, maintainable LLM applications. They enable you to compose simple building blocks into sophisticated workflows while maintaining clear separation of concerns and robust error handling.