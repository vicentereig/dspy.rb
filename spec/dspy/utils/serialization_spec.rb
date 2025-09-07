# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe DSPy::Utils::Serialization do
  describe '.deep_serialize' do
    context 'with T::Struct objects' do
      class SerializationSimpleStruct < T::Struct
        const :name, String
        const :value, Integer
      end

      class SerializationNestedStruct < T::Struct
        const :title, String
        const :simple, SerializationSimpleStruct
      end

      it 'serializes a simple T::Struct to a hash' do
        struct = SerializationSimpleStruct.new(name: 'test', value: 42)
        result = described_class.deep_serialize(struct)
        
        expect(result).to eq({ 'name' => 'test', 'value' => 42 })
        expect(result).to be_a(Hash)
      end

      it 'recursively serializes nested T::Struct objects' do
        simple = SerializationSimpleStruct.new(name: 'nested', value: 100)
        nested = SerializationNestedStruct.new(title: 'container', simple: simple)
        result = described_class.deep_serialize(nested)
        
        expect(result).to eq({
          'title' => 'container',
          'simple' => { 'name' => 'nested', 'value' => 100 }
        })
      end

      it 'handles T::Struct objects inside hashes' do
        struct = SerializationSimpleStruct.new(name: 'example', value: 123)
        hash = { action: struct, message: 'hello' }
        result = described_class.deep_serialize(hash)
        
        expect(result).to eq({
          action: { 'name' => 'example', 'value' => 123 },
          message: 'hello'
        })
      end

      it 'handles T::Struct objects inside arrays' do
        struct1 = SerializationSimpleStruct.new(name: 'first', value: 1)
        struct2 = SerializationSimpleStruct.new(name: 'second', value: 2)
        array = [struct1, struct2, 'plain string']
        result = described_class.deep_serialize(array)
        
        expect(result).to eq([
          { 'name' => 'first', 'value' => 1 },
          { 'name' => 'second', 'value' => 2 },
          'plain string'
        ])
      end

      it 'handles deeply nested combinations' do
        struct = SerializationSimpleStruct.new(name: 'deep', value: 999)
        complex = {
          data: [
            { item: struct, count: 5 },
            'string',
            123
          ],
          metadata: struct
        }
        result = described_class.deep_serialize(complex)
        
        expect(result).to eq({
          data: [
            { item: { 'name' => 'deep', 'value' => 999 }, count: 5 },
            'string',
            123
          ],
          metadata: { 'name' => 'deep', 'value' => 999 }
        })
      end
    end

    context 'with primitive values' do
      it 'returns strings unchanged' do
        result = described_class.deep_serialize('hello')
        expect(result).to eq('hello')
      end

      it 'returns numbers unchanged' do
        result = described_class.deep_serialize(42)
        expect(result).to eq(42)
      end

      it 'returns booleans unchanged' do
        result = described_class.deep_serialize(true)
        expect(result).to eq(true)
      end

      it 'returns nil unchanged' do
        result = described_class.deep_serialize(nil)
        expect(result).to be_nil
      end
    end

    context 'with plain hashes and arrays' do
      it 'processes plain hashes recursively' do
        hash = { a: 1, b: { c: 2 } }
        result = described_class.deep_serialize(hash)
        expect(result).to eq(hash)
      end

      it 'processes plain arrays recursively' do
        array = [1, [2, 3], { a: 4 }]
        result = described_class.deep_serialize(array)
        expect(result).to eq(array)
      end
    end
  end

  describe '.to_json' do
    class JsonTestStruct < T::Struct
      const :setup, String
      const :punchline, String
    end

    it 'converts T::Struct to valid JSON' do
      struct = JsonTestStruct.new(setup: 'Why did the coffee file a police report?', punchline: 'It got mugged!')
      result = described_class.to_json(struct)
      
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed).to eq({
        'setup' => 'Why did the coffee file a police report?',
        'punchline' => 'It got mugged!'
      })
    end

    it 'converts complex objects with T::Struct to valid JSON' do
      struct = JsonTestStruct.new(setup: 'Test setup', punchline: 'Test punchline')
      complex = { action: struct, message: 'test message', items: [struct] }
      result = described_class.to_json(complex)
      
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed).to eq({
        'action' => { 'setup' => 'Test setup', 'punchline' => 'Test punchline' },
        'message' => 'test message',
        'items' => [{ 'setup' => 'Test setup', 'punchline' => 'Test punchline' }]
      })
    end

    it 'handles objects without T::Struct normally' do
      plain_object = { message: 'hello', count: 42 }
      result = described_class.to_json(plain_object)
      
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed).to eq({ 'message' => 'hello', 'count' => 42 })
    end
  end
end