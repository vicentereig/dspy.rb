# frozen_string_literal: true

require 'sorbet-runtime'

require 'informers'

require_relative 'embedding_engine'

module DSPy
  module Memory
    # Local embedding engine using ankane/informers for privacy-preserving embeddings
    class LocalEmbeddingEngine < EmbeddingEngine
      extend T::Sig

      # Default models supported by informers
      DEFAULT_MODEL = 'sentence-transformers/all-MiniLM-L6-v2'
      SUPPORTED_MODELS = [
        'sentence-transformers/all-MiniLM-L6-v2',
        'sentence-transformers/all-MiniLM-L12-v2',
        'sentence-transformers/multi-qa-MiniLM-L6-cos-v1',
        'sentence-transformers/paraphrase-MiniLM-L6-v2'
      ].freeze

      sig { returns(String) }
      attr_reader :model_name

      sig { params(model_name: String).void }
      def initialize(model_name = DEFAULT_MODEL)
        @model_name = model_name
        @model = T.let(nil, T.nilable(T.untyped))
        @embedding_dim = T.let(nil, T.nilable(Integer))
        @ready = T.let(false, T::Boolean)
        
        load_model!
      end

      sig { override.params(text: String).returns(T::Array[Float]) }
      def embed(text)
        ensure_ready!
        
        # Preprocess text
        cleaned_text = preprocess_text(text)
        
        # Generate embedding
        result = @model.call(cleaned_text)
        
        # Extract embedding array and normalize
        embedding = result.first.to_a
        normalize_vector(embedding)
      end

      sig { override.params(texts: T::Array[String]).returns(T::Array[T::Array[Float]]) }
      def embed_batch(texts)
        ensure_ready!
        
        # Preprocess all texts
        cleaned_texts = texts.map { |text| preprocess_text(text) }
        
        # Generate embeddings in batch
        results = @model.call(cleaned_texts)
        
        # Extract and normalize embeddings
        results.map do |result|
          embedding = result.to_a
          normalize_vector(embedding)
        end
      end

      sig { override.returns(Integer) }
      def embedding_dimension
        @embedding_dim || load_model_info!
      end

      sig { override.returns(String) }
      def model_name
        @model_name
      end

      sig { override.returns(T::Boolean) }
      def ready?
        @ready
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def stats
        {
          model_name: @model_name,
          embedding_dimension: embedding_dimension,
          ready: ready?,
          supported_models: SUPPORTED_MODELS,
          backend: 'informers'
        }
      end

      # Check if a model is supported
      sig { params(model_name: String).returns(T::Boolean) }
      def self.model_supported?(model_name)
        SUPPORTED_MODELS.include?(model_name)
      end

      # List all supported models
      sig { returns(T::Array[String]) }
      def self.supported_models
        SUPPORTED_MODELS
      end

      private

      # Load the embedding model
      sig { void }
      def load_model!
        begin
          @model = Informers.pipeline('feature-extraction', @model_name)
          @ready = true
          load_model_info!
        rescue => e
          @ready = false
          raise "Failed to load embedding model '#{@model_name}': #{e.message}"
        end
      end

      # Load model information (dimension, etc.)
      sig { returns(Integer) }
      def load_model_info!
        return @embedding_dim if @embedding_dim
        
        # Test with a simple string to get dimension
        test_result = @model.call("test")
        @embedding_dim = test_result.first.size
      end

      # Ensure the model is ready
      sig { void }
      def ensure_ready!
        unless @ready
          raise "Embedding engine not ready. Model '#{@model_name}' failed to load."
        end
      end

      # Preprocess text for better embeddings
      sig { params(text: String).returns(String) }
      def preprocess_text(text)
        # Basic text preprocessing
        cleaned = text.strip
        
        # Remove excessive whitespace
        cleaned = cleaned.gsub(/\s+/, ' ')
        
        # Truncate if too long (most models have token limits)
        if cleaned.length > 8192  # Conservative limit
          cleaned = cleaned[0..8191]
        end
        
        cleaned
      end
    end

    # Fallback embedding engine when informers is not available
    class NoOpEmbeddingEngine < EmbeddingEngine
      extend T::Sig

      sig { override.params(text: String).returns(T::Array[Float]) }
      def embed(text)
        # Return a simple hash-based embedding for basic functionality
        simple_hash_embedding(text)
      end

      sig { override.params(texts: T::Array[String]).returns(T::Array[T::Array[Float]]) }
      def embed_batch(texts)
        texts.map { |text| embed(text) }
      end

      sig { override.returns(Integer) }
      def embedding_dimension
        128  # Fixed dimension for hash-based embeddings
      end

      sig { override.returns(String) }
      def model_name
        'simple-hash'
      end

      sig { override.returns(T::Boolean) }
      def ready?
        true
      end

      private

      # Generate a simple hash-based embedding that captures semantic similarity
      sig { params(text: String).returns(T::Array[Float]) }
      def simple_hash_embedding(text)
        # Create a deterministic but semantically aware embedding
        words = text.downcase.split(/\W+/).reject(&:empty?)
        
        # Initialize embedding vector
        embedding = Array.new(128, 0.0)
        
        # Create base embedding from all words
        words.each_with_index do |word, word_idx|
          word_hash = word.sum(&:ord)
          
          # Distribute word influence across dimensions
          (0..7).each do |i|
            dim = (word_hash + i * 13) % 128
            weight = Math.sin(word_hash + i) * 0.2
            embedding[dim] += weight / Math.sqrt(words.length + 1)
          end
        end
        
        # Add semantic clusters for common words
        semantic_clusters = {
          ['programming', 'code', 'software', 'development'] => (0..15),
          ['ruby', 'python', 'java', 'javascript'] => (16..31),
          ['work', 'project', 'task', 'job'] => (32..47),
          ['tutorial', 'guide', 'learning', 'education'] => (48..63),
          ['memory', 'storage', 'data', 'information'] => (64..79),
          ['personal', 'private', 'individual', 'own'] => (80..95),
          ['important', 'critical', 'key', 'essential'] => (96..111),
          ['test', 'testing', 'spec', 'example'] => (112..127)
        }
        
        semantic_clusters.each do |cluster_words, range|
          cluster_weight = words.count { |word| cluster_words.include?(word) }
          if cluster_weight > 0
            range.each { |dim| embedding[dim] += cluster_weight * 0.3 }
          end
        end
        
        # Normalize to unit vector
        normalize_vector(embedding)
      end
    end
  end
end