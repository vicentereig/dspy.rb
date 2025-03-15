require 'spec_helper'

RSpec.describe DSPy do
  describe 'initial setup' do
    it 'has a working test environment' do
      expect(true).to be true
    end

    it 'defines the DSPy module' do
      expect(defined?(DSPy)).to eq('constant')
    end
  end
end 