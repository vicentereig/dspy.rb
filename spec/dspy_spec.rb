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

  describe 'configuration' do
    it 'has lm setting' do
      expect(DSPy.config).to respond_to(:lm)
    end

    it 'has logger setting' do
      expect(DSPy.config).to respond_to(:logger)
      expect(DSPy.config.logger).to be_a(Dry::Logger::Dispatcher)
    end

    it 'has structured_outputs setting' do
      expect(DSPy.config).to respond_to(:structured_outputs)
      expect(DSPy.config.structured_outputs).to respond_to(:openai)
      expect(DSPy.config.structured_outputs).to respond_to(:anthropic)
    end

    it 'has test_mode setting' do
      expect(DSPy.config).to respond_to(:test_mode)
      expect(DSPy.config.test_mode).to eq(false)
    end

    it 'supports configuration blocks' do
      DSPy.configure do |config|
        config.test_mode = true
        config.structured_outputs.openai = true
      end

      expect(DSPy.config.test_mode).to eq(true)
      expect(DSPy.config.structured_outputs.openai).to eq(true)

      # Reset to defaults
      DSPy.configure do |config|
        config.test_mode = false
        config.structured_outputs.openai = false
      end
    end
  end

  describe 'fiber-local LM context' do
    let(:mock_lm1) { double('LM1', model: 'model1') }
    let(:mock_lm2) { double('LM2', model: 'model2') }
    let(:mock_global_lm) { double('GlobalLM', model: 'global') }

    before do
      # Clear any existing fiber-local context
      Fiber[:dspy_fiber_lm] = nil
      
      # Set global LM
      DSPy.configure do |config|
        config.lm = mock_global_lm
      end
    end

    after do
      # Clean up fiber-local context
      Fiber[:dspy_fiber_lm] = nil
      
      # Reset global config
      DSPy.configure do |config|
        config.lm = nil
      end
    end

    describe '.current_lm' do
      it 'returns global LM when no fiber-local context' do
        expect(DSPy.current_lm).to eq(mock_global_lm)
      end

      it 'returns fiber-local LM when set' do
        Fiber[:dspy_fiber_lm] = mock_lm1
        expect(DSPy.current_lm).to eq(mock_lm1)
      end

      it 'returns global LM when fiber-local is nil' do
        Fiber[:dspy_fiber_lm] = nil
        expect(DSPy.current_lm).to eq(mock_global_lm)
      end
    end

    describe '.with_lm' do
      it 'temporarily sets fiber-local LM' do
        expect(DSPy.current_lm).to eq(mock_global_lm)
        
        DSPy.with_lm(mock_lm1) do
          expect(DSPy.current_lm).to eq(mock_lm1)
        end
        
        expect(DSPy.current_lm).to eq(mock_global_lm)
      end

      it 'supports nested with_lm calls' do
        DSPy.with_lm(mock_lm1) do
          expect(DSPy.current_lm).to eq(mock_lm1)
          
          DSPy.with_lm(mock_lm2) do
            expect(DSPy.current_lm).to eq(mock_lm2)
          end
          
          expect(DSPy.current_lm).to eq(mock_lm1)
        end
        
        expect(DSPy.current_lm).to eq(mock_global_lm)
      end

      it 'restores previous context even when exception occurs' do
        expect do
          DSPy.with_lm(mock_lm1) do
            expect(DSPy.current_lm).to eq(mock_lm1)
            raise StandardError, "test error"
          end
        end.to raise_error(StandardError, "test error")
        
        expect(DSPy.current_lm).to eq(mock_global_lm)
      end

      it 'returns the block result' do
        result = DSPy.with_lm(mock_lm1) do
          "block result"
        end
        
        expect(result).to eq("block result")
      end
    end
  end
end 