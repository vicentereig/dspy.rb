# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'nullable and omittable field semantics' do
  class NullableOmittableSignature < DSPy::Signature
    input do
      const :required_nullable, T.nilable(String)
      const :omittable_nullable, T.nilable(String), default: nil
      const :items, T::Array[String], default: []
      const :mode, String, default: 'standard'
    end

    output do
      const :required_nullable, T.nilable(String)
      const :omittable_nullable, T.nilable(String), default: nil
      const :items, T::Array[String], default: []
      const :mode, String, default: 'standard'
    end
  end

  class NullableConstStruct < T::Struct
    const :note, T.nilable(String)
  end

  class NullablePropStruct < T::Struct
    prop :note, T.nilable(String)
  end

  class DefaultedStruct < T::Struct
    const :items, T::Array[String], default: []
    const :mode, String, default: 'standard'
  end

  class StubLM
    attr_accessor :response

    def initialize(response)
      @response = response
    end

    def chat(_predictor, _inputs)
      response
    end

    def schema_format
      nil
    end

    def data_format
      nil
    end
  end

  it 'uses defaults, not nilability, to determine signature requiredness' do
    [NullableOmittableSignature.input_json_schema, NullableOmittableSignature.output_json_schema].each do |schema|
      expect(schema[:required]).to eq(['required_nullable'])
      expect(schema[:properties][:required_nullable][:type]).to eq(%w[string null])
      expect(schema[:properties][:omittable_nullable][:type]).to eq(%w[string null])
      expect(schema[:properties][:items][:type]).to eq('array')
    end
  end

  it 'accepts explicit nil and applies nullable, array, and non-nil defaults' do
    [NullableOmittableSignature.input_schema, NullableOmittableSignature.output_schema].each do |struct_class|
      value = struct_class.new(required_nullable: nil)

      expect(value.required_nullable).to be_nil
      expect(value.omittable_nullable).to be_nil
      expect(value.items).to eq([])
      expect(value.mode).to eq('standard')
      expect { struct_class.new }.to raise_error(ArgumentError, /required_nullable/)
      expect { struct_class.new(required_nullable: nil, items: nil) }.to raise_error(TypeError)
    end
  end

  it 'preserves positional-hash and keyword construction' do
    input = NullableOmittableSignature.input_schema

    expect(input.new({ required_nullable: nil }).items).to eq([])
    expect(input.new(required_nullable: nil).items).to eq([])
    expect { input.new({ required_nullable: nil }, required_nullable: nil) }
      .to raise_error(ArgumentError, /one positional hash/)
    expect { input.new('invalid') }.to raise_error(ArgumentError, /one positional hash/)
  end

  it 'documents Sorbet constructor behavior for nilable const and prop fields' do
    expect(NullableConstStruct.new.note).to be_nil
    expect(NullableConstStruct.new(note: nil).note).to be_nil
    expect(NullablePropStruct.new.note).to be_nil
    expect(NullablePropStruct.new(note: nil).note).to be_nil
  end

  it 'keeps non-null defaulted arrays required in nested struct schemas' do
    value = DefaultedStruct.new
    schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(DefaultedStruct)

    expect(value.items).to eq([])
    expect(value.mode).to eq('standard')
    expect(schema[:required]).to include('items', 'mode')
    expect(schema[:properties][:items]).to eq(type: 'array', items: { type: 'string' })
  end


  it 'rejects omitted required-nullable model output in the prediction path' do
    predictor = DSPy::Predict.new(NullableOmittableSignature)
    predictor.configure { |config| config.lm = StubLM.new({}) }

    expect { predictor.call(required_nullable: nil) }
      .to raise_error(DSPy::PredictionInvalidError, /required_nullable/)
  end

  it 'accepts explicit nil and applies defaults in the prediction path' do
    predictor = DSPy::Predict.new(NullableOmittableSignature)
    predictor.configure do |config|
      config.lm = StubLM.new({ required_nullable: nil })
    end

    result = predictor.call(required_nullable: nil)

    expect(result.required_nullable).to be_nil
    expect(result.omittable_nullable).to be_nil
    expect(result.items).to eq([])
    expect(result.mode).to eq('standard')
  end
end
