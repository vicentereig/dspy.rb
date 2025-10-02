# frozen_string_literal: true

# This test demonstrates what would have failed before the enum coercion fix
# To see the failure, comment out lines 171-183 in lib/dspy/mixins/type_coercion.rb

require 'spec_helper'

class Size < T::Enum
  enums do
    Small = new('small')
    Medium = new('medium')
    Large = new('large')
  end
end

class DrinkOrder < T::Struct
  const :drink_type, String
  const :size, Size
  const :customizations, T::Array[String]
end

class RefundRequest < T::Struct
  const :order_id, String
  const :amount, Float
end

RSpec.describe 'TypeCoercion enum handling regression test' do
  include DSPy::Mixins::TypeCoercion
  
  it 'demonstrates the enum coercion bug that was fixed' do
    # This is the exact scenario from the coffee shop example
    union_type = T.any(DrinkOrder, RefundRequest)
    
    # LLM returns this hash with string value for enum field
    hash_from_llm = {
      "_type" => "DrinkOrder",
      "drink_type" => "iced latte",
      "size" => "large",  # String instead of Size enum
      "customizations" => ["oat milk", "extra shot"]
    }
    
    # Before fix: TypeError: Can't set DrinkOrder.size to "large" - need a Size
    # After fix: Correctly converts to Size::Large enum
    result = coerce_value_to_type(hash_from_llm, union_type)
    
    expect(result).to be_a(DrinkOrder)
    expect(result.size).to be_a(Size)
    expect(result.size).to eq(Size::Large)
    expect(result.drink_type).to eq("iced latte")
    expect(result.customizations).to eq(["oat milk", "extra shot"])
  end
  
  it 'handles nested type coercion including floats in union types' do
    union_type = T.any(DrinkOrder, RefundRequest)
    
    hash_from_llm = {
      "_type" => "RefundRequest",
      "order_id" => "12345",
      "amount" => "5.99"  # String that needs float conversion
    }
    
    result = coerce_value_to_type(hash_from_llm, union_type)
    
    expect(result).to be_a(RefundRequest)
    expect(result.amount).to be_a(Float)
    expect(result.amount).to eq(5.99)
  end
end