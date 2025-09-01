---
layout: docs
name: Multi-stage Pipelines
description: Build complex workflows by composing DSPy modules
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: Multi-stage Pipelines
  url: "/advanced/pipelines/"
prev:
  name: Complex Types
  url: "/advanced/complex-types/"
next:
  name: Retrieval Augmented Generation
  url: "/advanced/rag/"
date: 2025-07-10 00:00:00 +0000
---
# Multi-stage Pipelines

DSPy.rb supports building complex, multi-stage pipelines by composing multiple DSPy modules together. You can create sequential workflows, conditional processing, and reusable pipeline components for sophisticated LLM applications.

## Overview

DSPy.rb enables pipeline creation through:
- **Module Composition**: Combine multiple DSPy::Module instances
- **Sequential Processing**: Chain operations in order
- **Data Flow**: Pass results between pipeline stages
- **Error Handling**: Graceful failure management
- **Reusable Components**: Build modular, testable pipelines

## Basic Pipeline Concepts

### Module-Based Architecture

```ruby
# Individual modules for each stage
class DocumentClassificationSignature < DSPy::Signature
  description "Classify document type"
  input { const :content, String }
  output { const :document_type, String }
end

class DocumentClassifier < DSPy::Module
  def initialize
    super
    @predictor = DSPy::Predict.new(DocumentClassificationSignature)
  end

  def forward(content:)
    @predictor.call(content: content)
  end
end

class SummaryGenerationSignature < DSPy::Signature
  description "Generate document summary"
  input { const :content, String }
  output { const :summary, String }
end

class SummaryGenerator < DSPy::Module
  def initialize
    super
    @predictor = DSPy::Predict.new(SummaryGenerationSignature)
  end

  def forward(content:)
    @predictor.call(content: content)
  end
end
```

### Sequential Pipeline

```ruby
class DocumentProcessor < DSPy::Module
  def initialize
    super
    @classifier = DocumentClassifier.new
    @summarizer = SummaryGenerator.new
  end

  def forward(content:)
    # Stage 1: Classify document
    classification = @classifier.call(content: content)
    
    # Stage 2: Generate summary
    summary = @summarizer.call(content: content)
    
    # Return combined results
    {
      document_type: classification.document_type,
      summary: summary.summary,
      original_length: content.length,
      summary_length: summary.summary.length
    }
  end
end

# Usage
processor = DocumentProcessor.new
result = processor.call(content: "Long document content...")

puts "Type: #{result[:document_type]}"
puts "Summary: #{result[:summary]}"
```

## Advanced Pipeline Patterns

### Conditional Processing

```ruby
class AdaptiveDocumentProcessor < DSPy::Module
  def initialize
    super
    @classifier = DocumentClassifier.new
    @technical_summarizer = TechnicalSummarizer.new
    @general_summarizer = GeneralSummarizer.new
    @legal_analyzer = LegalAnalyzer.new
  end

  def forward(content:)
    # Stage 1: Classify
    classification = @classifier.call(content: content)
    doc_type = classification.document_type
    
    # Stage 2: Conditional processing based on type
    case doc_type.downcase
    when 'technical'
      summary = @technical_summarizer.call(content: content)
      analysis = nil
    when 'legal'
      summary = @general_summarizer.call(content: content)
      analysis = @legal_analyzer.call(content: content)
    else
      summary = @general_summarizer.call(content: content)
      analysis = nil
    end
    
    # Combine results
    result = {
      document_type: doc_type,
      summary: summary.summary
    }
    
    result[:legal_analysis] = analysis if analysis
    result
  end
end
```

### Pipeline with Error Handling

```ruby
class RobustPipeline < DSPy::Module
  def initialize
    super
    @stages = [
      DocumentClassifier.new,
      SummaryGenerator.new,
      KeywordExtractor.new
    ]
  end

  def forward(content:)
    results = { input_length: content.length }
    current_content = content
    
    @stages.each_with_index do |stage, index|
      begin
        case index
        when 0 # Classification
          result = stage.call(content: current_content)
          results[:document_type] = result.document_type
        when 1 # Summarization
          result = stage.call(content: current_content)
          results[:summary] = result.summary
          current_content = result.summary # Use summary for next stage
        when 2 # Keyword extraction
          result = stage.call(content: current_content)
          results[:keywords] = result.keywords
        end
      rescue => e
        results[:errors] ||= []
        results[:errors] << {
          stage: index,
          stage_name: stage.class.name,
          error: e.message
        }
        
        # Continue with original content if stage fails
        current_content = content
      end
    end
    
    results
  end
end
```

### Data Transformation Pipeline

```ruby
class EmailProcessor < DSPy::Module
  def initialize
    super
    @spam_detector = SpamDetector.new
    @sentiment_analyzer = SentimentAnalyzer.new
    @priority_classifier = PriorityClassifier.new
    @response_generator = ResponseGenerator.new
  end

  def forward(email_content:, sender:)
    pipeline_data = {
      content: email_content,
      sender: sender,
      processing_steps: []
    }
    
    # Stage 1: Spam detection
    spam_result = @spam_detector.call(content: email_content)
    pipeline_data[:is_spam] = spam_result.is_spam
    pipeline_data[:processing_steps] << "spam_detection"
    
    # Skip further processing if spam
    return pipeline_data if pipeline_data[:is_spam]
    
    # Stage 2: Sentiment analysis
    sentiment_result = @sentiment_analyzer.call(content: email_content)
    pipeline_data[:sentiment] = sentiment_result.sentiment
    pipeline_data[:processing_steps] << "sentiment_analysis"
    
    # Stage 3: Priority classification
    priority_result = @priority_classifier.call(
      content: email_content,
      sentiment: pipeline_data[:sentiment]
    )
    pipeline_data[:priority] = priority_result.priority
    pipeline_data[:processing_steps] << "priority_classification"
    
    # Stage 4: Generate response if high priority
    if priority_result.priority == "high"
      response_result = @response_generator.call(
        content: email_content,
        sentiment: pipeline_data[:sentiment]
      )
      pipeline_data[:suggested_response] = response_result.response
      pipeline_data[:processing_steps] << "response_generation"
    end
    
    pipeline_data
  end
end
```

## Parallel Processing Simulation

```ruby
class ParallelAnalysisPipeline < DSPy::Module
  def initialize
    super
    @analyzers = {
      sentiment: SentimentAnalyzer.new,
      topics: TopicExtractor.new,
      entities: EntityExtractor.new,
      readability: ReadabilityAnalyzer.new
    }
  end

  def forward(content:)
    # Simulate parallel processing with sequential calls
    # In a real implementation, you might use threads or async processing
    results = {}
    errors = {}
    
    @analyzers.each do |name, analyzer|
      begin
        start_time = Time.now
        result = analyzer.call(content: content)
        duration = Time.now - start_time
        
        results[name] = {
          result: result,
          processing_time: duration
        }
      rescue => e
        errors[name] = e.message
      end
    end
    
    {
      content_length: content.length,
      analysis_results: results,
      errors: errors,
      total_analyzers: @analyzers.size,
      successful_analyzers: results.size,
      failed_analyzers: errors.size
    }
  end
end
```

## Pipeline Optimization

### Caching Pipeline Results

```ruby
class CachedPipeline < DSPy::Module
  def initialize(base_pipeline)
    super
    @base_pipeline = base_pipeline
    @cache = {}
  end

  def forward(**inputs)
    cache_key = generate_cache_key(inputs)
    
    if @cache.key?(cache_key)
      puts "Cache hit for #{cache_key[0..10]}..."
      return @cache[cache_key]
    end
    
    puts "Cache miss, processing..."
    result = @base_pipeline.call(**inputs)
    
    # Store in cache (in production, consider cache size limits)
    @cache[cache_key] = result
    result
  end

  private

  def generate_cache_key(inputs)
    # Simple cache key generation
    Digest::SHA256.hexdigest(inputs.to_s)
  end
end

# Usage
base_processor = DocumentProcessor.new
cached_processor = CachedPipeline.new(base_processor)

# First call processes normally
result1 = cached_processor.call(content: document)

# Second call with same content uses cache
result2 = cached_processor.call(content: document)
```

### Performance Monitoring

```ruby
class MonitoredPipeline < DSPy::Module
  def initialize(base_pipeline)
    super
    @base_pipeline = base_pipeline
    @metrics = {
      total_calls: 0,
      total_time: 0.0,
      errors: 0
    }
  end

  def forward(**inputs)
    @metrics[:total_calls] += 1
    start_time = Time.now
    
    begin
      result = @base_pipeline.call(**inputs)
      
      # Add performance metadata
      duration = Time.now - start_time
      @metrics[:total_time] += duration
      
      result_with_metrics = result.dup
      result_with_metrics[:performance] = {
        processing_time: duration,
        average_time: @metrics[:total_time] / @metrics[:total_calls],
        call_number: @metrics[:total_calls]
      }
      
      result_with_metrics
    rescue => e
      @metrics[:errors] += 1
      duration = Time.now - start_time
      @metrics[:total_time] += duration
      
      raise e
    end
  end

  def stats
    {
      total_calls: @metrics[:total_calls],
      total_time: @metrics[:total_time],
      average_time: @metrics[:total_calls] > 0 ? @metrics[:total_time] / @metrics[:total_calls] : 0,
      error_rate: @metrics[:total_calls] > 0 ? @metrics[:errors].to_f / @metrics[:total_calls] : 0,
      errors: @metrics[:errors]
    }
  end
end

# Usage
base_pipeline = DocumentProcessor.new
monitored_pipeline = MonitoredPipeline.new(base_pipeline)

# Process documents
results = documents.map { |doc| monitored_pipeline.call(content: doc) }

# Check performance
puts "Pipeline stats: #{monitored_pipeline.stats}"
```

## Complex Pipeline Example

```ruby
class ContentAnalysisPipeline < DSPy::Module
  def initialize
    super
    
    # Initialize all pipeline stages
    @content_classifier = ContentClassifier.new
    @language_detector = LanguageDetector.new
    @sentiment_analyzer = SentimentAnalyzer.new
    @topic_extractor = TopicExtractor.new
    @summarizer = ContentSummarizer.new
    @quality_assessor = QualityAssessor.new
  end

  def forward(content:, metadata: {})
    analysis = {
      timestamp: Time.now,
      input_metadata: metadata,
      processing_chain: []
    }

    # Stage 1: Basic content analysis
    begin
      classification = @content_classifier.call(content: content)
      analysis[:content_type] = classification.content_type
      analysis[:processing_chain] << :content_classification
    rescue => e
      analysis[:errors] ||= []
      analysis[:errors] << { stage: :content_classification, error: e.message }
    end

    # Stage 2: Language detection
    begin
      language = @language_detector.call(content: content)
      analysis[:language] = language.language
      analysis[:language_confidence] = language.confidence
      analysis[:processing_chain] << :language_detection
    rescue => e
      analysis[:errors] ||= []
      analysis[:errors] << { stage: :language_detection, error: e.message }
      analysis[:language] = 'unknown'
    end

    # Stage 3: Sentiment analysis (only for certain content types)
    if ['article', 'review', 'social_post'].include?(analysis[:content_type])
      begin
        sentiment = @sentiment_analyzer.call(content: content)
        analysis[:sentiment] = sentiment.sentiment
        analysis[:sentiment_score] = sentiment.confidence
        analysis[:processing_chain] << :sentiment_analysis
      rescue => e
        analysis[:errors] ||= []
        analysis[:errors] << { stage: :sentiment_analysis, error: e.message }
      end
    end

    # Stage 4: Topic extraction
    begin
      topics = @topic_extractor.call(content: content)
      analysis[:topics] = topics.topics
      analysis[:topic_confidence] = topics.confidence
      analysis[:processing_chain] << :topic_extraction
    rescue => e
      analysis[:errors] ||= []
      analysis[:errors] << { stage: :topic_extraction, error: e.message }
    end

    # Stage 5: Summarization (for long content)
    if content.length > 1000
      begin
        summary = @summarizer.call(content: content)
        analysis[:summary] = summary.summary
        analysis[:summary_ratio] = summary.summary.length.to_f / content.length
        analysis[:processing_chain] << :summarization
      rescue => e
        analysis[:errors] ||= []
        analysis[:errors] << { stage: :summarization, error: e.message }
      end
    end

    # Stage 6: Quality assessment
    begin
      quality = @quality_assessor.call(
        content: content,
        content_type: analysis[:content_type],
        language: analysis[:language]
      )
      analysis[:quality_score] = quality.score
      analysis[:quality_issues] = quality.issues
      analysis[:processing_chain] << :quality_assessment
    rescue => e
      analysis[:errors] ||= []
      analysis[:errors] << { stage: :quality_assessment, error: e.message }
    end

    # Add processing summary
    analysis[:processing_summary] = {
      total_stages: 6,
      completed_stages: analysis[:processing_chain].size,
      error_count: analysis[:errors]&.size || 0,
      processing_time: Time.now - analysis[:timestamp]
    }

    analysis
  end
end

# Usage
pipeline = ContentAnalysisPipeline.new

# Process a single document
result = pipeline.call(
  content: "Long article content...",
  metadata: { source: 'web', author: 'John Doe' }
)

puts "Content type: #{result[:content_type]}"
puts "Language: #{result[:language]}"
puts "Topics: #{result[:topics]}"
puts "Processing completed #{result[:processing_summary][:completed_stages]}/#{result[:processing_summary][:total_stages]} stages"
```

## Best Practices

### 1. Modular Design

```ruby
# Good: Each stage is a separate, testable module
class EmailTriagePipeline < DSPy::Module
  def initialize
    super
    @spam_filter = SpamFilter.new      # Focused responsibility
    @categorizer = EmailCategorizer.new # Single concern
    @prioritizer = PriorityAssigner.new # Clear purpose
  end
end

# Good: Reusable components
urgent_filter = PriorityAssigner.new
customer_emails = urgent_filter.call(emails: customer_emails)
support_emails = urgent_filter.call(emails: support_emails)
```

### 2. Error Recovery

```ruby
def forward_with_fallback(content:)
  begin
    # Try primary processing
    advanced_analysis(content)
  rescue AdvancedAnalysisError => e
    # Fall back to basic processing
    puts "Advanced analysis failed, using basic: #{e.message}"
    basic_analysis(content)
  rescue => e
    # Final fallback
    puts "All analysis failed: #{e.message}"
    { error: e.message, content_length: content.length }
  end
end
```

### 3. Pipeline Testing

```ruby
# Test individual stages
describe DocumentClassifier do
  it "classifies technical documents" do
    classifier = DocumentClassifier.new
    result = classifier.call(content: "API documentation...")
    expect(result.document_type).to eq("technical")
  end
end

# Test full pipeline
describe DocumentProcessor do
  it "processes documents end-to-end" do
    processor = DocumentProcessor.new
    result = processor.call(content: sample_document)
    
    expect(result).to have_key(:document_type)
    expect(result).to have_key(:summary)
    expect(result[:summary]).not_to be_empty
  end
end
```

### 4. Performance Considerations

```ruby
# Avoid reprocessing
class EfficientPipeline < DSPy::Module
  def forward(content:)
    # Process once, use multiple times
    base_analysis = analyze_content(content)
    
    {
      classification: classify_from_analysis(base_analysis),
      sentiment: sentiment_from_analysis(base_analysis),
      topics: topics_from_analysis(base_analysis)
    }
  end
end
```

