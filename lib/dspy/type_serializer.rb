# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class TypeSerializer
    extend T::Sig

    # Serialize a value, injecting _type fields for T::Struct instances
    sig { params(value: T.untyped).returns(T.untyped) }
    def self.serialize(value)
      case value
      when T::Struct
        serialize_struct(value)
      when Array
        value.map { |item| serialize(item) }
      when Hash
        value.transform_values { |v| serialize(v) }
      else
        value
      end
    end

    private

    sig { params(struct: T::Struct).returns(T::Hash[String, T.untyped]) }
    def self.serialize_struct(struct)
      result = {
        "_type" => struct.class.name.split('::').last
      }

      # Get all props and serialize their values
      struct.class.props.each do |prop_name, prop_info|
        prop_value = struct.send(prop_name)
        
        # Skip nil values for optional fields
        next if prop_value.nil? && prop_info[:fully_optional]
        
        # Recursively serialize nested values
        result[prop_name.to_s] = serialize(prop_value)
      end

      result
    end
  end
end