# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe 'DSPy::Module#save' do
  # Simple test module
  class SaveableTestModule < DSPy::Module
    def forward_untyped(**input_values)
      { result: "test" }
    end

    def to_h
      {
        class_name: self.class.name,
        state: { test_data: "value" }
      }
    end
  end

  let(:module_instance) { SaveableTestModule.new }

  it 'saves module state to JSON file' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'module.json')

      module_instance.save(path)

      expect(File.exist?(path)).to be(true)
    end
  end

  it 'writes valid JSON content' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'module.json')

      module_instance.save(path)

      content = JSON.parse(File.read(path), symbolize_names: true)
      expect(content).to be_a(Hash)
      expect(content[:class_name]).to eq('SaveableTestModule')
      expect(content[:state]).to be_a(Hash)
    end
  end

  it 'saves serialized data from to_h method' do
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, 'module.json')

      module_instance.save(path)

      content = JSON.parse(File.read(path), symbolize_names: true)
      expect(content[:state][:test_data]).to eq('value')
    end
  end

  it 'creates parent directories if they do not exist' do
    Dir.mktmpdir do |tmpdir|
      nested_path = File.join(tmpdir, 'nested', 'dir', 'module.json')

      module_instance.save(nested_path)

      expect(File.exist?(nested_path)).to be(true)
    end
  end
end
