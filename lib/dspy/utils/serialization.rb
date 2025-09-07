# typed: strict
# frozen_string_literal: true

module DSPy
  module Utils
    class Serialization
      extend T::Sig

      # Deep serializes any T::Struct objects to hashes for observability
      sig { params(obj: T.untyped).returns(T.untyped) }
      def self.deep_serialize(obj)
        case obj
        when T::Struct
          # Use the serialize method to convert to a plain hash
          deep_serialize(obj.serialize)
        when Hash
          # Recursively serialize hash values
          obj.transform_values { |v| deep_serialize(v) }
        when Array
          # Recursively serialize array elements
          obj.map { |v| deep_serialize(v) }
        else
          # Return primitive values as-is
          obj
        end
      end

      # Serializes an object to JSON with proper T::Struct handling
      sig { params(obj: T.untyped).returns(String) }
      def self.to_json(obj)
        deep_serialize(obj).to_json
      end
    end
  end
end