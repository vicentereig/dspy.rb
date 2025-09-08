---
layout: docs
name: Retrieval Augmented Generation (RAG)
description: Build RAG applications with DSPy.rb
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: RAG
  url: "/advanced/rag/"
prev:
  name: Multi-stage Pipelines
  url: "/advanced/pipelines/"
next:
  name: Custom Metrics
  url: "/advanced/custom-metrics/"
date: 2025-07-10 00:00:00 +0000
---
# Retrieval Augmented Generation (RAG)

DSPy.rb supports building RAG (Retrieval Augmented Generation) applications by combining retrieval systems with LLM-powered reasoning. While the framework doesn't provide built-in vector stores or embedding models, you can integrate external retrieval services and build sophisticated RAG pipelines.

## Overview

RAG in DSPy.rb involves:
- **External Retrieval Integration**: Connect to vector databases and search services
- **Context-Aware Signatures**: Design signatures that work with retrieved context
- **Multi-Step Reasoning**: Chain retrieval and generation steps
- **Manual Implementation**: Build custom RAG workflows using DSPy modules

## Basic RAG Implementation

### Simple RAG with External Service

```ruby
# Define a signature for context-based question answering
class ContextualQA < DSPy::Signature
  description "Answer questions using provided context"
  
  input do
    const :question, String
    const :context, String
  end
  
  output do
    const :answer, String
    const :confidence, Float
  end
end

# Basic RAG module
class SimpleRAG < DSPy::Module
  def initialize(retrieval_service)
    super
    @retrieval_service = retrieval_service
    @qa_predictor = DSPy::Predict.new(ContextualQA)
  end

  def forward(question:)
    # Step 1: Retrieve relevant context
    context = @retrieval_service.search(question)
    
    # Step 2: Generate answer with context
    result = @qa_predictor.call(
      question: question,
      context: context
    )
    
    {
      question: question,
      context: context,
      answer: result.answer,
      confidence: result.confidence
    }
  end
end

# Example retrieval service integration
class ColBERTRetriever
  def initialize(base_url)
    @base_url = base_url
  end

  def search(query, k: 5)
    # Integration with external ColBERT service
    response = HTTP.get("#{@base_url}/search", 
                       params: { query: query, k: k })
    
    if response.success?
      results = JSON.parse(response.body)
      results['passages'].join('\n\n')
    else
      ""
    end
  end
end

# Usage
retriever = ColBERTRetriever.new("http://localhost:8080")
rag_system = SimpleRAG.new(retriever)

result = rag_system.call(question: "What is machine learning?")
puts "Answer: #{result[:answer]}"
puts "Context used: #{result[:context][0..100]}..."
```

### Multi-Step RAG Pipeline

```ruby
class AdvancedRAG < DSPy::Module
  def initialize(retrieval_service)
    super
    @retrieval_service = retrieval_service
    
    # Multiple specialized predictors
    @question_analyzer = DSPy::Predict.new(QuestionAnalysis)
    @context_evaluator = DSPy::Predict.new(ContextEvaluation)
    @answer_generator = DSPy::Predict.new(ContextualQA)
    @answer_validator = DSPy::Predict.new(AnswerValidation)
  end

  def forward(question:)
    pipeline_result = { question: question, steps: [] }
    
    # Step 1: Analyze question complexity
    question_analysis = @question_analyzer.call(question: question)
    pipeline_result[:question_type] = question_analysis.question_type
    pipeline_result[:complexity] = question_analysis.complexity
    pipeline_result[:steps] << "question_analysis"
    
    # Step 2: Retrieve context (adjust based on complexity)
    num_passages = question_analysis.complexity == "high" ? 10 : 5
    context = @retrieval_service.search(question, k: num_passages)
    pipeline_result[:context] = context
    pipeline_result[:steps] << "retrieval"
    
    # Step 3: Evaluate context relevance
    context_eval = @context_evaluator.call(
      question: question,
      context: context
    )
    pipeline_result[:context_relevance] = context_eval.relevance_score
    pipeline_result[:steps] << "context_evaluation"
    
    # Step 4: Generate answer
    answer_result = @answer_generator.call(
      question: question,
      context: context
    )
    pipeline_result[:answer] = answer_result.answer
    pipeline_result[:confidence] = answer_result.confidence
    pipeline_result[:steps] << "answer_generation"
    
    # Step 5: Validate answer
    validation = @answer_validator.call(
      question: question,
      answer: answer_result.answer,
      context: context
    )
    pipeline_result[:validation_score] = validation.score
    pipeline_result[:validation_issues] = validation.issues
    pipeline_result[:steps] << "answer_validation"
    
    pipeline_result
  end
end

# Supporting signatures
class QuestionAnalysis < DSPy::Signature
  description "Analyze question complexity and type"
  
  input do
    const :question, String
  end
  
  output do
    const :question_type, String
    const :complexity, String  # "low", "medium", "high"
    const :requires_multiple_sources, T::Boolean
  end
end

class ContextEvaluation < DSPy::Signature
  description "Evaluate context relevance to question"
  
  input do
    const :question, String
    const :context, String
  end
  
  output do
    const :relevance_score, Float
    const :missing_information, String
  end
end

class AnswerValidation < DSPy::Signature
  description "Validate answer quality and accuracy"
  
  input do
    const :question, String
    const :answer, String
    const :context, String
  end
  
  output do
    const :score, Float
    const :issues, T::Array[String]
    const :supported_by_context, T::Boolean
  end
end
```

## RAG with Filtering and Reranking

```ruby
class FilteredRAG < DSPy::Module
  def initialize(retrieval_service)
    super
    @retrieval_service = retrieval_service
    @relevance_filter = DSPy::Predict.new(RelevanceFilter)
    @context_ranker = DSPy::Predict.new(ContextRanker)
    @qa_predictor = DSPy::Predict.new(ContextualQA)
  end

  def forward(question:, max_passages: 3)
    # Step 1: Initial retrieval (get more than needed)
    raw_passages = @retrieval_service.search(question, k: max_passages * 2)
    passages = raw_passages.split('\n\n')
    
    # Step 2: Filter for relevance
    filtered_passages = []
    passages.each do |passage|
      relevance = @relevance_filter.call(
        question: question,
        passage: passage
      )
      
      if relevance.is_relevant
        filtered_passages << {
          text: passage,
          relevance_score: relevance.score
        }
      end
    end
    
    # Step 3: Rerank passages
    if filtered_passages.size > max_passages
      # Use top passages by relevance score
      top_passages = filtered_passages
                      .sort_by { |p| -p[:relevance_score] }
                      .first(max_passages)
      
      context = top_passages.map { |p| p[:text] }.join('\n\n')
    else
      context = filtered_passages.map { |p| p[:text] }.join('\n\n')
    end
    
    # Step 4: Generate answer
    result = @qa_predictor.call(
      question: question,
      context: context
    )
    
    {
      question: question,
      context: context,
      answer: result.answer,
      confidence: result.confidence,
      passages_used: filtered_passages.size,
      passages_filtered: passages.size - filtered_passages.size
    }
  end
end

class RelevanceFilter < DSPy::Signature
  description "Determine if passage is relevant to question"
  
  input do
    const :question, String
    const :passage, String
  end
  
  output do
    const :is_relevant, T::Boolean
    const :score, Float
    const :reasoning, String
  end
end

class ContextRanker < DSPy::Signature
  description "Rank context passages by relevance"
  
  input do
    const :question, String
    const :passages, T::Array[String]
  end
  
  output do
    const :ranked_passages, T::Array[String]
    const :relevance_scores, T::Array[Float]
  end
end
```

## Integration with External Services

### Vector Database Integration

```ruby
# Example integration with a vector database
class VectorDBRetriever
  def initialize(connection_string, collection_name)
    @connection_string = connection_string
    @collection_name = collection_name
    # Initialize your vector DB client here
  end

  def search(query, k: 5, similarity_threshold: 0.7)
    # Implement vector similarity search
    # This is a placeholder - actual implementation depends on your vector DB
    
    begin
      # Convert query to embedding
      embedding = generate_embedding(query)
      
      # Search vector database
      results = vector_db_search(embedding, k: k)
      
      # Filter by similarity threshold
      relevant_results = results.select { |r| r[:similarity] >= similarity_threshold }
      
      # Extract text content
      relevant_results.map { |r| r[:text] }.join('\n\n')
    rescue => e
      puts "Vector search failed: #{e.message}"
      ""
    end
  end

  private

  def generate_embedding(text)
    # Integrate with your embedding service
    # e.g., OpenAI embeddings, SentenceTransformers, etc.
  end

  def vector_db_search(embedding, k:)
    # Implement actual vector database search
    # Return array of { text: "...", similarity: 0.85 }
  end
end
```

### Hybrid Search Implementation

```ruby
class HybridRetriever
  def initialize(vector_retriever, keyword_retriever)
    @vector_retriever = vector_retriever
    @keyword_retriever = keyword_retriever
  end

  def search(query, k: 5, vector_weight: 0.7)
    # Perform both vector and keyword search
    vector_results = @vector_retriever.search(query, k: k)
    keyword_results = @keyword_retriever.search(query, k: k)
    
    # Combine and deduplicate results
    combined_passages = [
      vector_results.split('\n\n'),
      keyword_results.split('\n\n')
    ].flatten.uniq
    
    # Take top k passages
    combined_passages.first(k).join('\n\n')
  end
end

class KeywordRetriever
  def initialize(search_service)
    @search_service = search_service
  end

  def search(query, k: 5)
    # Implement keyword-based search (e.g., Elasticsearch, Solr)
    results = @search_service.search(query, limit: k)
    results.map { |r| r['content'] }.join('\n\n')
  end
end
```

## RAG Evaluation

```ruby
class RAGEvaluator
  def initialize
    @answer_evaluator = DSPy::Predict.new(AnswerEvaluation)
    @context_evaluator = DSPy::Predict.new(ContextualAnswerEvaluation)
  end

  def evaluate_rag_system(rag_system, test_questions)
    results = []
    
    test_questions.each do |test_case|
      result = rag_system.call(question: test_case[:question])
      
      # Evaluate answer quality
      answer_eval = @answer_evaluator.call(
        question: test_case[:question],
        answer: result[:answer],
        expected_answer: test_case[:expected_answer]
      )
      
      # Evaluate context usage
      context_eval = @context_evaluator.call(
        question: test_case[:question],
        answer: result[:answer],
        context: result[:context]
      )
      
      results << {
        question: test_case[:question],
        answer: result[:answer],
        expected: test_case[:expected_answer],
        answer_quality: answer_eval.score,
        context_usage: context_eval.score,
        supported_by_context: context_eval.well_supported
      }
    end
    
    # Calculate aggregate metrics
    avg_answer_quality = results.map { |r| r[:answer_quality] }.sum / results.size
    avg_context_usage = results.map { |r| r[:context_usage] }.sum / results.size
    
    {
      individual_results: results,
      aggregate_metrics: {
        average_answer_quality: avg_answer_quality,
        average_context_usage: avg_context_usage,
        total_questions: results.size
      }
    }
  end
end

class AnswerEvaluation < DSPy::Signature
  description "Evaluate answer quality against expected answer"
  
  input do
    const :question, String
    const :answer, String
    const :expected_answer, String
  end
  
  output do
    const :score, Float
    const :reasoning, String
  end
end

class ContextualAnswerEvaluation < DSPy::Signature
  description "Evaluate how well answer uses provided context"
  
  input do
    const :question, String
    const :answer, String
    const :context, String
  end
  
  output do
    const :score, Float
    const :well_supported, T::Boolean
    const :missing_context, String
  end
end
```

## Best Practices

### 1. Design Context-Aware Signatures

```ruby
# Good: Clear context handling
class ContextualSummary < DSPy::Signature
  description "Summarize information from multiple sources"
  
  input do
    const :topic, String
    const :sources, String  # Multiple passages separated by \n\n
  end
  
  output do
    const :summary, String
    const :key_points, T::Array[String]
    const :source_coverage, Float
  end
end
```

### 2. Handle Retrieval Failures

```ruby
def forward_with_fallback(question:)
  begin
    context = @retrieval_service.search(question)
    
    if context.empty?
      # Fallback to general knowledge
      return generate_general_answer(question)
    end
    
    generate_contextual_answer(question, context)
  rescue => e
    puts "Retrieval failed: #{e.message}"
    generate_general_answer(question)
  end
end
```

### 3. Optimize Context Length

```ruby
def prepare_context(passages, max_length: 2000)
  context = ""
  
  passages.each do |passage|
    if (context + passage).length <= max_length
      context += passage + "\n\n"
    else
      break
    end
  end
  
  context.strip
end
```

### 4. Monitor RAG Performance

```ruby
def call_with_monitoring(question:)
  start_time = Time.now
  
  result = forward(question: question)
  
  # Add monitoring data
  result[:monitoring] = {
    processing_time: Time.now - start_time,
    context_length: result[:context].length,
    question_length: question.length
  }
  
  result
end
```

