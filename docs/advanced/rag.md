# RAG Implementation

Retrieval Augmented Generation (RAG) combines the power of DSPy predictors with external knowledge retrieval, enabling accurate responses grounded in specific data sources.

## Basic RAG Setup

### Simple Document RAG

```ruby
class SimpleRAG < DSPy::Module
  def initialize(documents)
    @documents = documents
    @retriever = DocumentRetriever.new(documents)
    @generator = DSPy::Predict.new(GenerateAnswerFromContext)
  end
  
  def call(question)
    # Retrieve relevant documents
    relevant_docs = @retriever.retrieve(question, limit: 3)
    
    # Generate answer with context
    answer = @generator.call(
      question: question,
      context: relevant_docs.map(&:content).join("\n\n"),
      source_count: relevant_docs.size
    )
    
    RAGResult.new(
      question: question,
      answer: answer.answer,
      confidence: answer.confidence,
      sources: relevant_docs,
      retrieval_score: calculate_retrieval_score(relevant_docs)
    )
  end
end

class GenerateAnswerFromContext < DSPy::Signature
  description "Generate accurate answer based on provided context"
  
  input do
    const :question, String
    const :context, String
    const :source_count, Integer
  end
  
  output do
    const :answer, String
    const :confidence, Float
    const :context_used, T::Boolean
  end
end
```

### Vector-based RAG

```ruby
class VectorRAG < DSPy::Module
  def initialize(knowledge_base_path)
    @vector_store = VectorStore.new(knowledge_base_path)
    @embedder = EmbeddingModel.new
    @generator = DSPy::ChainOfThought.new(GenerateWithReasoning)
  end
  
  def call(query)
    # Generate query embedding
    query_embedding = @embedder.embed(query)
    
    # Retrieve similar documents
    similar_docs = @vector_store.similarity_search(
      embedding: query_embedding,
      limit: 5,
      threshold: 0.7
    )
    
    # Rank documents by relevance
    ranked_docs = rank_documents(query, similar_docs)
    
    # Generate answer with reasoning
    result = @generator.call(
      query: query,
      documents: format_documents(ranked_docs),
      retrieval_metadata: build_retrieval_metadata(ranked_docs)
    )
    
    VectorRAGResult.new(
      query: query,
      answer: result.answer,
      reasoning: result.reasoning,
      sources: ranked_docs,
      embedding_similarity: calculate_avg_similarity(similar_docs)
    )
  end
  
  private
  
  def rank_documents(query, documents)
    # Re-rank using cross-encoder or other relevance model
    query_terms = extract_key_terms(query)
    
    documents.map do |doc|
      relevance_score = calculate_relevance(query_terms, doc.content)
      doc.with_relevance_score(relevance_score)
    end.sort_by(&:relevance_score).reverse
  end
end
```

## Advanced RAG Patterns

### Multi-step RAG

```ruby
class MultiStepRAG < DSPy::Module
  def initialize(knowledge_sources)
    @sources = knowledge_sources
    @query_analyzer = DSPy::ChainOfThought.new(AnalyzeQuery)
    @retriever = MultiSourceRetriever.new(knowledge_sources)
    @synthesizer = DSPy::ChainOfThought.new(SynthesizeFromSources)
  end
  
  def call(complex_query)
    # Step 1: Analyze query complexity and requirements
    analysis = @query_analyzer.call(query: complex_query)
    
    # Step 2: Generate sub-queries if needed
    sub_queries = generate_sub_queries(complex_query, analysis)
    
    # Step 3: Retrieve for each sub-query
    retrieval_results = sub_queries.map do |sub_query|
      {
        sub_query: sub_query,
        documents: @retriever.retrieve(
          query: sub_query,
          sources: select_sources(sub_query, analysis),
          strategy: analysis.retrieval_strategy
        )
      }
    end
    
    # Step 4: Synthesize comprehensive answer
    synthesis = @synthesizer.call(
      original_query: complex_query,
      query_analysis: analysis,
      retrieval_results: retrieval_results,
      synthesis_strategy: analysis.synthesis_strategy
    )
    
    MultiStepRAGResult.new(
      original_query: complex_query,
      query_analysis: analysis,
      sub_queries: sub_queries,
      retrieval_results: retrieval_results,
      final_answer: synthesis.answer,
      reasoning_trace: synthesis.reasoning,
      confidence: synthesis.confidence
    )
  end
  
  private
  
  def generate_sub_queries(query, analysis)
    case analysis.complexity_level
    when 'high'
      decompose_complex_query(query, analysis.query_aspects)
    when 'medium'
      [query, generate_clarifying_query(query)]
    else
      [query]
    end
  end
end
```

### Agentic RAG

```ruby
class AgenticRAG < DSPy::Module
  def initialize(knowledge_base, tools: [])
    @knowledge_base = knowledge_base
    @tools = tools + [SearchTool.new(knowledge_base)]
    @agent = DSPy::React.new(AgenticRAGSignature, tools: @tools)
  end
  
  def call(user_query)
    @agent.call(
      user_query: user_query,
      available_sources: @knowledge_base.list_sources,
      search_capabilities: describe_search_capabilities
    )
  end
end

class AgenticRAGSignature < DSPy::Signature
  description "Use available tools to research and answer user queries comprehensively"
  
  input do
    const :user_query, String
    const :available_sources, T::Array[String]
    const :search_capabilities, String
  end
  
  output do
    const :answer, String
    const :sources_consulted, T::Array[String]
    const :research_strategy, String
    const :confidence, Float
  end
end

class SearchTool < DSPy::Tools::Base
  def initialize(knowledge_base)
    @kb = knowledge_base
  end
  
  def search_documents(query, source: nil, limit: 5)
    results = @kb.search(
      query: query,
      source_filter: source,
      limit: limit
    )
    
    {
      results: results.map(&:to_h),
      total_found: results.size,
      search_query: query,
      source_searched: source
    }
  end
  
  def get_document_details(document_id)
    doc = @kb.get_document(document_id)
    
    {
      title: doc.title,
      content: doc.content,
      metadata: doc.metadata,
      last_updated: doc.updated_at
    }
  end
end
```

## RAG with Multiple Knowledge Sources

### Federated RAG

```ruby
class FederatedRAG < DSPy::Module
  def initialize
    @retrievers = {
      documents: DocumentRetriever.new,
      database: DatabaseRetriever.new,
      web: WebRetriever.new,
      apis: APIRetriever.new
    }
    @source_selector = DSPy::Predict.new(SelectSources)
    @answer_generator = DSPy::ChainOfThought.new(GenerateFromMultipleSources)
  end
  
  def call(query)
    # Step 1: Determine which sources to query
    source_selection = @source_selector.call(
      query: query,
      available_sources: @retrievers.keys.map(&:to_s)
    )
    
    # Step 2: Query selected sources in parallel
    retrieval_results = Async do |task|
      source_selection.selected_sources.map do |source|
        task.async do
          retriever = @retrievers[source.to_sym]
          {
            source: source,
            results: retriever.retrieve(query, **source_selection.source_params[source])
          }
        end
      end.map(&:wait)
    end
    
    # Step 3: Generate answer from all sources
    answer = @answer_generator.call(
      query: query,
      source_results: retrieval_results,
      source_reliability: assess_source_reliability(retrieval_results)
    )
    
    FederatedRAGResult.new(
      query: query,
      sources_consulted: source_selection.selected_sources,
      retrieval_results: retrieval_results,
      answer: answer.answer,
      reasoning: answer.reasoning,
      source_attribution: answer.source_attribution
    )
  end
end
```

### Hierarchical RAG

```ruby
class HierarchicalRAG < DSPy::Module
  def initialize(document_hierarchy)
    @hierarchy = document_hierarchy
    @summary_retriever = SummaryRetriever.new(document_hierarchy.summaries)
    @detail_retriever = DetailRetriever.new(document_hierarchy.details)
    @section_retriever = SectionRetriever.new(document_hierarchy.sections)
    @answer_synthesizer = DSPy::ChainOfThought.new(SynthesizeHierarchicalAnswer)
  end
  
  def call(query)
    # Step 1: Search at summary level
    relevant_summaries = @summary_retriever.retrieve(query, limit: 10)
    
    # Step 2: For promising summaries, get detailed sections
    detailed_sections = relevant_summaries.flat_map do |summary|
      @section_retriever.retrieve_from_document(
        query: query,
        document_id: summary.document_id,
        limit: 3
      )
    end
    
    # Step 3: For high-relevance sections, get full details
    full_details = detailed_sections
      .select { |section| section.relevance_score > 0.8 }
      .flat_map do |section|
        @detail_retriever.retrieve_from_section(
          query: query,
          section_id: section.id,
          limit: 2
        )
      end
    
    # Step 4: Synthesize answer from hierarchical context
    answer = @answer_synthesizer.call(
      query: query,
      summaries: relevant_summaries,
      sections: detailed_sections,
      details: full_details,
      hierarchy_depth: calculate_hierarchy_depth([relevant_summaries, detailed_sections, full_details])
    )
    
    HierarchicalRAGResult.new(
      query: query,
      summaries_found: relevant_summaries.size,
      sections_found: detailed_sections.size,
      details_found: full_details.size,
      answer: answer.answer,
      reasoning: answer.reasoning,
      hierarchy_path: answer.hierarchy_path
    )
  end
end
```

## RAG Quality and Evaluation

### RAG Evaluation Metrics

```ruby
class RAGEvaluator
  def initialize
    @relevance_checker = DSPy::Predict.new(CheckRelevance)
    @faithfulness_checker = DSPy::Predict.new(CheckFaithfulness)
    @completeness_checker = DSPy::Predict.new(CheckCompleteness)
  end
  
  def evaluate(rag_result, ground_truth: nil)
    metrics = {}
    
    # Retrieval metrics
    metrics[:retrieval] = evaluate_retrieval(rag_result)
    
    # Generation metrics
    metrics[:generation] = evaluate_generation(rag_result)
    
    # End-to-end metrics
    metrics[:end_to_end] = evaluate_end_to_end(rag_result, ground_truth)
    
    # Quality metrics
    metrics[:quality] = evaluate_answer_quality(rag_result)
    
    RAGEvaluationResult.new(
      overall_score: calculate_overall_score(metrics),
      detailed_metrics: metrics,
      recommendations: generate_improvement_recommendations(metrics)
    )
  end
  
  private
  
  def evaluate_retrieval(rag_result)
    {
      precision: calculate_retrieval_precision(rag_result.sources),
      recall: calculate_retrieval_recall(rag_result.sources),
      relevance_score: calculate_avg_relevance(rag_result.sources),
      source_diversity: calculate_source_diversity(rag_result.sources)
    }
  end
  
  def evaluate_generation(rag_result)
    faithfulness = @faithfulness_checker.call(
      answer: rag_result.answer,
      context: rag_result.sources.map(&:content).join("\n")
    )
    
    relevance = @relevance_checker.call(
      query: rag_result.query,
      answer: rag_result.answer
    )
    
    {
      faithfulness: faithfulness.score,
      relevance: relevance.score,
      coherence: assess_coherence(rag_result.answer),
      completeness: assess_completeness(rag_result.answer, rag_result.query)
    }
  end
end
```

### RAG Optimization

```ruby
class RAGOptimizer
  def initialize(rag_system)
    @rag_system = rag_system
    @evaluator = RAGEvaluator.new
    @optimization_history = []
  end
  
  def optimize(test_queries, ground_truth_answers)
    current_performance = evaluate_current_performance(test_queries, ground_truth_answers)
    best_performance = current_performance
    best_config = @rag_system.current_config
    
    optimization_strategies = [
      :adjust_retrieval_parameters,
      :optimize_chunk_size,
      :tune_similarity_threshold,
      :improve_query_expansion,
      :enhance_reranking
    ]
    
    optimization_strategies.each do |strategy|
      config_variants = generate_config_variants(strategy)
      
      config_variants.each do |config|
        @rag_system.update_config(config)
        performance = evaluate_current_performance(test_queries, ground_truth_answers)
        
        if performance > best_performance
          best_performance = performance
          best_config = config
        end
        
        @optimization_history << {
          strategy: strategy,
          config: config,
          performance: performance,
          timestamp: Time.current
        }
      end
    end
    
    # Apply best configuration
    @rag_system.update_config(best_config)
    
    RAGOptimizationResult.new(
      initial_performance: current_performance,
      final_performance: best_performance,
      best_config: best_config,
      improvement: best_performance - current_performance,
      optimization_history: @optimization_history
    )
  end
  
  private
  
  def generate_config_variants(strategy)
    case strategy
    when :adjust_retrieval_parameters
      [
        { top_k: 3, threshold: 0.7 },
        { top_k: 5, threshold: 0.6 },
        { top_k: 7, threshold: 0.8 }
      ]
    when :optimize_chunk_size
      [
        { chunk_size: 200, overlap: 50 },
        { chunk_size: 500, overlap: 100 },
        { chunk_size: 1000, overlap: 200 }
      ]
    # ... other strategies
    end
  end
end
```

## Production RAG Considerations

### Caching and Performance

```ruby
class CachedRAG < DSPy::Module
  def initialize(base_rag, cache_store: Rails.cache)
    @base_rag = base_rag
    @cache = cache_store
  end
  
  def call(query)
    # Check for cached results
    cache_key = generate_cache_key(query)
    
    if cached_result = @cache.read(cache_key)
      return cached_result.merge(cache_hit: true)
    end
    
    # Generate new result
    result = @base_rag.call(query)
    
    # Cache with appropriate TTL
    cache_ttl = determine_cache_ttl(result)
    @cache.write(cache_key, result, expires_in: cache_ttl)
    
    result.merge(cache_hit: false)
  end
  
  private
  
  def determine_cache_ttl(result)
    # Longer cache for high-confidence results
    case result.confidence
    when 0.9..1.0
      4.hours
    when 0.7...0.9
      1.hour
    else
      15.minutes
    end
  end
end
```

### Monitoring and Observability

```ruby
class MonitoredRAG < DSPy::Module
  def initialize(base_rag)
    @base_rag = base_rag
  end
  
  def call(query)
    start_time = Time.current
    
    result = @base_rag.call(query)
    
    # Record metrics
    record_rag_metrics(query, result, Time.current - start_time)
    
    result
  end
  
  private
  
  def record_rag_metrics(query, result, duration)
    DSPy.metrics.histogram('rag.query_duration').record(duration)
    DSPy.metrics.histogram('rag.sources_retrieved').record(result.sources.size)
    DSPy.metrics.histogram('rag.confidence').record(result.confidence)
    DSPy.metrics.counter('rag.queries_total').increment
    
    # Track query characteristics
    DSPy.metrics.histogram('rag.query_length').record(query.length)
    
    # Track result quality
    if result.confidence > 0.8
      DSPy.metrics.counter('rag.high_confidence_answers').increment
    end
  end
end
```

## Testing RAG Systems

### Unit Testing

```ruby
RSpec.describe SimpleRAG do
  let(:documents) { load_test_documents }
  let(:rag) { described_class.new(documents) }
  
  describe "#call" do
    it "retrieves relevant documents for query" do
      result = rag.call("What is machine learning?")
      
      expect(result.sources).not_to be_empty
      expect(result.sources.all? { |s| s.content.include?('machine learning') }).to be true
    end
    
    it "generates coherent answers" do
      result = rag.call("Explain neural networks")
      
      expect(result.answer).to be_present
      expect(result.answer.length).to be > 50
      expect(result.confidence).to be_between(0.0, 1.0)
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "RAG Integration" do
  let(:knowledge_base) { build_test_knowledge_base }
  let(:rag) { VectorRAG.new(knowledge_base.path) }
  
  it "handles complex multi-part queries" do
    query = "How do transformers work and what are their advantages over RNNs?"
    
    result = rag.call(query)
    
    expect(result.answer).to include('transformer')
    expect(result.answer).to include('attention')
    expect(result.sources.size).to be >= 2
  end
  
  it "maintains performance under load" do
    queries = generate_test_queries(100)
    
    execution_time = Benchmark.realtime do
      queries.each { |query| rag.call(query) }
    end
    
    expect(execution_time / queries.size).to be < 2.0  # Average < 2 seconds per query
  end
end
```

RAG systems enable DSPy applications to leverage external knowledge while maintaining the benefits of structured generation and type safety. Use these patterns to build knowledge-grounded applications that can answer questions accurately from your specific data sources.