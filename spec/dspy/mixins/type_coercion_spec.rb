# frozen_string_literal: true

require 'spec_helper'

# Test enums
class Priority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
  end
end

# Test structs for union type handling
module TestStructs
  class SearchAction < T::Struct
    const :query, String
    const :max_results, Integer, default: 5
  end

  class AnswerAction < T::Struct
    const :content, String
    const :confidence, Float
  end
  
  class TaskAction < T::Struct
    const :title, String
    const :priority, Priority  # Enum field
  end
end

RSpec.describe DSPy::Mixins::TypeCoercion do
  # Create a test class that includes the mixin
  let(:test_class) do
    Class.new do
      include DSPy::Mixins::TypeCoercion
      
      def test_coerce(value, type)
        coerce_value_to_type(value, type)
      end
      
      def test_coerce_attributes(attributes, props)
        coerce_output_attributes(attributes, props)
      end
    end
  end
  
  let(:instance) { test_class.new }
  
  describe '#coerce_value_to_type' do
    context 'with union types (T.any)' do
      let(:union_type) { T.any(TestStructs::SearchAction, TestStructs::AnswerAction) }
      
      it 'converts Hash with enum fields within union types' do
        # Test with union type including a struct with enum field
        union_with_enum = T.any(TestStructs::TaskAction, TestStructs::AnswerAction)
        
        hash_value = {
          "_type" => "TaskAction",
          "title" => "Important task",
          "priority" => "high"  # String that needs enum conversion
        }
        
        result = instance.test_coerce(hash_value, union_with_enum)
        
        expect(result).to be_a(TestStructs::TaskAction)
        expect(result.title).to eq("Important task")
        expect(result.priority).to be_a(Priority)
        expect(result.priority).to eq(Priority::High)
      end
      
      it 'converts Hash with _type discriminator to appropriate struct' do
        # Test AnswerAction conversion
        hash_value = {
          "_type" => "AnswerAction",
          "content" => "2 + 2 = 4",
          "confidence" => 1.0
        }
        
        result = instance.test_coerce(hash_value, union_type)
        
        expect(result).to be_a(TestStructs::AnswerAction)
        expect(result.content).to eq("2 + 2 = 4")
        expect(result.confidence).to eq(1.0)
      end
      
      it 'converts Hash with symbol keys and _type to appropriate struct' do
        hash_value = {
          _type: "SearchAction",
          query: "AI safety research",
          max_results: 10
        }
        
        result = instance.test_coerce(hash_value, union_type)
        
        expect(result).to be_a(TestStructs::SearchAction)
        expect(result.query).to eq("AI safety research")
        expect(result.max_results).to eq(10)
      end
      
      it 'returns original value if no _type field present' do
        hash_value = {
          "query" => "test query",
          "max_results" => 5
        }
        
        result = instance.test_coerce(hash_value, union_type)
        
        # Without _type, it should return the original hash
        expect(result).to eq(hash_value)
      end
      
      it 'returns original value if _type does not match any union variant' do
        hash_value = {
          "_type" => "UnknownAction",
          "data" => "some data"
        }
        
        result = instance.test_coerce(hash_value, union_type)
        
        expect(result).to eq(hash_value)
      end
    end
    
    context 'with existing type handling' do
      it 'still handles simple types correctly' do
        # Use T::Utils.coerce to get proper Sorbet type objects
        float_type = T::Utils.coerce(Float)
        integer_type = T::Utils.coerce(Integer)
        
        expect(instance.test_coerce("3.14", float_type)).to eq(3.14)
        expect(instance.test_coerce("42", integer_type)).to eq(42)
      end
      
      it 'still handles arrays correctly' do
        array_type = T::Array[Integer]
        result = instance.test_coerce(["1", "2", "3"], array_type)
        expect(result).to eq([1, 2, 3])
      end
      
      it 'still handles regular structs correctly' do
        struct_type = TestStructs::AnswerAction
        hash_value = { content: "Answer", confidence: 0.9 }
        
        result = instance.test_coerce(hash_value, struct_type)
        
        expect(result).to be_a(TestStructs::AnswerAction)
        expect(result.content).to eq("Answer")
        expect(result.confidence).to eq(0.9)
      end
    end
  end
  
  describe '#coerce_output_attributes' do
    it 'handles mixed attributes including union types' do
      props = {
        status: { type: T::Utils.coerce(String) },
        action: { type: T.any(TestStructs::SearchAction, TestStructs::AnswerAction) },
        confidence: { type: T::Utils.coerce(Float) }
      }
      
      attributes = {
        status: "success",
        action: {
          "_type" => "AnswerAction",
          "content" => "The answer is 42",
          "confidence" => 0.95
        },
        confidence: "0.99"
      }
      
      result = instance.test_coerce_attributes(attributes, props)
      
      expect(result[:status]).to eq("success")
      expect(result[:action]).to be_a(TestStructs::AnswerAction)
      expect(result[:action].content).to eq("The answer is 42")
      expect(result[:confidence]).to eq(0.99)
    end
  end
end