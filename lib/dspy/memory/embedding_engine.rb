# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Memory
    # Abstract base class for embedding engines
    class EmbeddingEngine
      extend T::Sig
      extend T::Helpers
      abstract!

      # Generate embeddings for a single text
      sig { abstract.params(text: String).returns(T::Array[Float]) }
      def embed(text); end

      # Generate embeddings for multiple texts (batch processing)
      sig { abstract.params(texts: T::Array[String]).returns(T::Array[T::Array[Float]]) }
      def embed_batch(texts); end

      # Get the dimension of embeddings produced by this engine
      sig { abstract.returns(Integer) }
      def embedding_dimension; end

      # Get the model name/identifier
      sig { abstract.returns(String) }
      def model_name; end

      # Check if the engine is ready to use
      sig { returns(T::Boolean) }
      def ready?
        true
      end

      # Get engine statistics
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def stats
        {
          model_name: model_name,
          embedding_dimension: embedding_dimension,
          ready: ready?
        }
      end

      # Normalize a vector to unit length
      sig { params(vector: T::Array[Float]).returns(T::Array[Float]) }
      def normalize_vector(vector)
        magnitude = Math.sqrt(vector.sum { |x| x * x })
        return vector if magnitude == 0.0
        vector.map { |x| x / magnitude }
      end

      # Calculate cosine similarity between two vectors
      sig { params(a: T::Array[Float], b: T::Array[Float]).returns(Float) }
      def cosine_similarity(a, b)
        return 0.0 if a.empty? || b.empty? || a.size != b.size
        
        dot_product = a.zip(b).sum { |x, y| x * y }
        magnitude_a = Math.sqrt(a.sum { |x| x * x })
        magnitude_b = Math.sqrt(b.sum { |x| x * x })
        
        return 0.0 if magnitude_a == 0.0 || magnitude_b == 0.0
        
        dot_product / (magnitude_a * magnitude_b)
      end
    end
  end
end