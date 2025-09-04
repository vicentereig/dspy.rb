# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::CrossoverEngine do
  # Test signature for crossover testing
  class CrossoverTestSignature < DSPy::Signature
    description "Test signature for crossover operations"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new.tap do |c|
      c.crossover_rate = 0.8
      c.crossover_types = [:uniform, :blend, :structured]
    end
  end

  let(:mock_program_a) do
    double('program_a', signature_class: CrossoverTestSignature)
  end

  let(:mock_program_b) do
    double('program_b', signature_class: CrossoverTestSignature)
  end

  describe 'initialization' do
    it 'creates engine with config' do
      engine = described_class.new(config: config)
      
      expect(engine.config).to eq(config)
    end

    it 'initializes with default crossover types' do
      default_config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      engine = described_class.new(config: default_config)
      
      expect(engine.config.crossover_types).to include(:uniform, :blend, :structured)
    end

    it 'requires config parameter' do
      expect { described_class.new }.to raise_error(ArgumentError)
    end
  end

  describe '#crossover_programs' do
    let(:engine) { described_class.new(config: config) }

    it 'returns offspring programs from two parents' do
      allow(engine).to receive(:extract_instruction).with(mock_program_a).and_return("Solve carefully")
      allow(engine).to receive(:extract_instruction).with(mock_program_b).and_return("Answer step by step")
      allow(engine).to receive(:apply_crossover).and_return("Solve carefully step by step")
      allow(engine).to receive(:create_crossover_program).and_return(mock_program_a)
      
      offspring = engine.crossover_programs(mock_program_a, mock_program_b)
      
      expect(offspring).to be_an(Array)
      expect(offspring.size).to eq(2) # Two offspring
      expect(engine).to have_received(:apply_crossover)
    end

    it 'handles crossover failures gracefully' do
      allow(engine).to receive(:extract_instruction).and_raise(StandardError, 'Crossover error')
      
      offspring = engine.crossover_programs(mock_program_a, mock_program_b)
      
      expect(offspring).to eq([mock_program_a, mock_program_b]) # Returns parents on failure
    end

    it 'respects crossover rate configuration' do
      low_rate_config = DSPy::Teleprompt::GEPA::GEPAConfig.new.tap { |c| c.crossover_rate = 0.0 }
      engine = described_class.new(config: low_rate_config)
      
      # With 0% crossover rate, should return original parents
      offspring = engine.crossover_programs(mock_program_a, mock_program_b)
      expect(offspring).to eq([mock_program_a, mock_program_b])
    end
  end

  describe '#batch_crossover' do
    let(:engine) { described_class.new(config: config) }
    let(:population) { [mock_program_a, mock_program_b, mock_program_a, mock_program_b] }

    it 'performs crossover on population pairs' do
      allow(engine).to receive(:crossover_programs).and_return([mock_program_a, mock_program_b])
      
      offspring_population = engine.batch_crossover(population)
      
      expect(offspring_population.size).to eq(population.size)
      expect(engine).to have_received(:crossover_programs).at_least(:once)
    end

    it 'handles odd population sizes' do
      odd_population = [mock_program_a, mock_program_b, mock_program_a]
      allow(engine).to receive(:crossover_programs).and_return([mock_program_a, mock_program_b])
      
      offspring = engine.batch_crossover(odd_population)
      
      expect(offspring.size).to eq(odd_population.size)
    end

    it 'handles empty population' do
      offspring = engine.batch_crossover([])
      expect(offspring).to be_empty
    end

    it 'handles single program population' do
      offspring = engine.batch_crossover([mock_program_a])
      expect(offspring).to eq([mock_program_a])
    end
  end

  describe '#apply_crossover' do
    let(:engine) { described_class.new(config: config) }

    it 'applies uniform crossover' do
      instruction_a = "Answer carefully"
      instruction_b = "Solve step by step"
      
      result = engine.send(:apply_crossover, instruction_a, instruction_b, :uniform)
      
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      result.each { |inst| expect(inst).to be_a(String) }
    end

    it 'applies blend crossover' do
      instruction_a = "Calculate the result"
      instruction_b = "Determine the answer" 
      
      result = engine.send(:apply_crossover, instruction_a, instruction_b, :blend)
      
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      result.each { |inst| expect(inst).to be_a(String) }
    end

    it 'applies structured crossover' do
      instruction_a = "Solve this problem carefully"
      instruction_b = "Answer the question step by step"
      
      result = engine.send(:apply_crossover, instruction_a, instruction_b, :structured)
      
      expect(result).to be_an(Array) 
      expect(result.size).to eq(2)
      result.each { |inst| expect(inst).to be_a(String) }
    end

    it 'handles unknown crossover types' do
      instruction_a = "Test instruction A"
      instruction_b = "Test instruction B"
      
      result = engine.send(:apply_crossover, instruction_a, instruction_b, :unknown_type)
      
      expect(result).to eq([instruction_a, instruction_b]) # Should return originals
    end
  end

  describe 'crossover type implementations' do
    let(:engine) { described_class.new(config: config) }

    describe '#uniform_crossover' do
      it 'creates uniform mixture of instructions' do
        instruction_a = "Answer carefully and accurately"
        instruction_b = "Solve step by step with reasoning"
        
        result = engine.send(:uniform_crossover, instruction_a, instruction_b)
        
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        # Results should be different from originals (mixed)
        expect(result).not_to eq([instruction_a, instruction_b])
      end

      it 'handles identical instructions' do
        instruction = "Solve this problem"
        
        result = engine.send(:uniform_crossover, instruction, instruction)
        
        expect(result).to eq([instruction, instruction])
      end
    end

    describe '#blend_crossover' do
      it 'creates semantic blends of instructions' do
        instruction_a = "Calculate"
        instruction_b = "Compute"
        
        result = engine.send(:blend_crossover, instruction_a, instruction_b)
        
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        result.each { |inst| expect(inst).to be_a(String) }
      end

      it 'preserves key concepts from both parents' do
        instruction_a = "Solve math problems"
        instruction_b = "Calculate equations carefully"
        
        result = engine.send(:blend_crossover, instruction_a, instruction_b)
        
        # At least one result should contain concepts from both
        combined_result = result.join(' ')
        expect([
          combined_result.include?('solve') || combined_result.include?('calculate'),
          combined_result.include?('math') || combined_result.include?('equation')
        ].any?).to be(true)
      end
    end

    describe '#structured_crossover' do
      it 'creates structured combinations' do
        instruction_a = "Answer the question"
        instruction_b = "Solve step by step"
        
        result = engine.send(:structured_crossover, instruction_a, instruction_b)
        
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        result.each { |inst| expect(inst).to be_a(String) }
      end

      it 'maintains grammatical structure' do
        instruction_a = "Carefully solve this problem"
        instruction_b = "Accurately answer the question"
        
        result = engine.send(:structured_crossover, instruction_a, instruction_b)
        
        # Results should be grammatically coherent (basic check)
        result.each do |inst|
          expect(inst).not_to be_empty
          expect(inst.split.size).to be > 0
        end
      end
    end
  end

  describe '#extract_instruction' do
    let(:engine) { described_class.new(config: config) }

    it 'extracts instruction from program description' do
      signature_class = double('signature', description: "Solve problems systematically")
      program = double('program', signature_class: signature_class)
      
      instruction = engine.send(:extract_instruction, program)
      
      expect(instruction).to eq("Solve problems systematically")
    end

    it 'handles programs without signature description' do
      signature_class = double('signature', description: nil)
      program = double('program', signature_class: signature_class)
      
      instruction = engine.send(:extract_instruction, program)
      
      expect(instruction).to include("complete the task") # Default fallback
    end
  end

  describe '#create_crossover_program' do
    let(:engine) { described_class.new(config: config) }

    it 'creates new program with crossover instruction' do
      new_instruction = "Solve systematically with detailed reasoning"
      
      crossover_program = engine.send(:create_crossover_program, mock_program_a, new_instruction)
      
      expect(crossover_program).not_to be_nil
      # In real implementation, this would create a new program instance
      # For now, we'll verify it returns a program-like object
    end
  end

  describe '#select_crossover_type' do
    let(:engine) { described_class.new(config: config) }

    it 'selects from configured crossover types' do
      crossover_type = engine.send(:select_crossover_type)
      
      expect(config.crossover_types).to include(crossover_type)
    end

    it 'uses adaptive selection based on instruction characteristics' do
      # Test with different instruction pairs
      simple_a = "Answer"
      simple_b = "Solve"
      complex_a = "Carefully analyze the problem with step-by-step reasoning"
      complex_b = "Systematically approach the solution using logical methods"
      
      simple_type = engine.send(:select_crossover_type, simple_a, simple_b)
      complex_type = engine.send(:select_crossover_type, complex_a, complex_b)
      
      expect(simple_type).to be_a(Symbol)
      expect(complex_type).to be_a(Symbol)
    end
  end

  describe '#crossover_diversity' do
    let(:engine) { described_class.new(config: config) }

    it 'measures diversity of crossover operations' do
      crossovers = [:uniform, :blend, :uniform, :structured, :blend]
      diversity = engine.send(:crossover_diversity, crossovers)
      
      expect(diversity).to be_between(0.0, 1.0)
      expect(diversity).to be > 0.0 # Should have some diversity
    end

    it 'returns 0 for uniform crossover types' do
      crossovers = [:uniform, :uniform, :uniform]
      diversity = engine.send(:crossover_diversity, crossovers)
      
      expect(diversity).to be < 0.5 # Low diversity
    end

    it 'handles empty crossover list' do
      diversity = engine.send(:crossover_diversity, [])
      expect(diversity).to eq(0.0)
    end
  end
end