---
layout: docs
title: "Ruby RAG Tutorial with DSPy.rb"
name: Retrieval Augmented Generation (RAG)
description: "Build retrieval-augmented generation in Ruby with external search, typed signatures, and evaluation."
date: 2025-07-10 00:00:00 +0000
---
# Retrieval Augmented Generation (RAG)

DSPy.rb does not provide a vector store or embedding model. A RAG program retrieves context through application code or a tool, then passes that context into a typed module.

## Assign Retrieval Ownership

- **Application code or a tool** calls the vector database or search service.
- **A signature** declares the retrieved context and answer fields.
- **Ruby control flow or an agent loop** decides whether to retrieve once or choose among retrieval tools.

## Build the Retrieval Boundary

### Call an External Retriever

```ruby
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

class SimpleRAG < DSPy::Module
  def initialize(retrieval_service)
    super
    @retrieval_service = retrieval_service
    @qa_predictor = DSPy::Predict.new(ContextualQA)
  end

  def forward(question:)
    context = @retrieval_service.search(question)
    
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
    
    question_analysis = @question_analyzer.call(question: question)
    pipeline_result[:question_type] = question_analysis.question_type
    pipeline_result[:complexity] = question_analysis.complexity
    pipeline_result[:steps] << "question_analysis"
    
    num_passages = question_analysis.complexity == "high" ? 10 : 5
    context = @retrieval_service.search(question, k: num_passages)
    pipeline_result[:context] = context
    pipeline_result[:steps] << "retrieval"
    
    context_eval = @context_evaluator.call(
      question: question,
      context: context
    )
    pipeline_result[:context_relevance] = context_eval.relevance_score
    pipeline_result[:steps] << "context_evaluation"
    
    answer_result = @answer_generator.call(
      question: question,
      context: context
    )
    pipeline_result[:answer] = answer_result.answer
    pipeline_result[:confidence] = answer_result.confidence
    pipeline_result[:steps] << "answer_generation"
    
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
    raw_passages = @retrieval_service.search(question, k: max_passages * 2)
    passages = raw_passages.split('\n\n')
    
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
    
    if filtered_passages.size > max_passages
      top_passages = filtered_passages
                      .sort_by { |p| -p[:relevance_score] }
                      .first(max_passages)
      
      context = top_passages.map { |p| p[:text] }.join('\n\n')
    else
      context = filtered_passages.map { |p| p[:text] }.join('\n\n')
    end
    
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

## Bound Retrieval and Context

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
  
  result[:monitoring] = {
    processing_time: Time.now - start_time,
    context_length: result[:context].length,
    question_length: question.length
  }
  
  result
end
```

## Continue by Reader Task

### Core Concepts
- **[Signatures](/dspy.rb/core-concepts/signatures/)** - Define the typed context and answer fields
- **[Modules](/dspy.rb/core-concepts/modules/)** - Compose retrieval and generation with Ruby control flow
- **[Stateful Agents](/dspy.rb/advanced/stateful-agents/)** - Pass application-owned persistent state into agent calls

### More Patterns
- **[Multi-stage Pipelines](/dspy.rb/advanced/pipelines/)** - Compose multiple retrieval and generation stages
- **[Custom Metrics](/dspy.rb/advanced/custom-metrics/)** - Define domain-specific evaluation metrics for RAG programs
- **[Rails Integration](/dspy.rb/advanced/rails-integration/)** - Put RAG calls behind Rails services and jobs

### Optimization
- **[MIPROv2](/dspy.rb/optimization/miprov2/)** - Optimize supported instructions and examples against a metric
- **[Evaluation](/dspy.rb/optimization/evaluation/)** - Measure retrieval and answer behavior with explicit metrics

### Framework Comparison
- **[DSPy.rb vs LangChain](/dspy.rb/advanced/dspy-vs-langchain/)** - Compare RAG capabilities between Ruby frameworks

### Production
- **[Observability](/dspy.rb/production/observability/)** - Trace retrieval and model calls
- **[Troubleshooting](/dspy.rb/production/troubleshooting/)** - Diagnose provider, parsing, and validation failures
