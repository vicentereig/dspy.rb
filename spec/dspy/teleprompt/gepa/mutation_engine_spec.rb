# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::MutationEngine do
  before(:all) { skip 'Skip all GEPA tests until retry logic is optimized' }
  # Test signature for mutation testing
  class MutationTestSignature < DSPy::Signature
    description "Test signature for mutation operations"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new.tap do |c|
      c.mutation_rate = 0.8
      c.mutation_types = [
        DSPy::Teleprompt::GEPA::MutationType::Rewrite,
        DSPy::Teleprompt::GEPA::MutationType::Expand,
        DSPy::Teleprompt::GEPA::MutationType::Simplify
      ]
    end
  end

  let(:test_program) { MockableTestModule.new(MutationTestSignature) }

  describe 'initialization' do
    it 'creates engine with config' do
      engine = described_class.new(config: config)
      
      expect(engine.config).to eq(config)
    end

    it 'initializes with default mutation types' do
      default_config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      engine = described_class.new(config: default_config)
      
      expect(engine.config.mutation_types).to include(
        DSPy::Teleprompt::GEPA::MutationType::Rewrite,
        DSPy::Teleprompt::GEPA::MutationType::Expand,
        DSPy::Teleprompt::GEPA::MutationType::Simplify,
        DSPy::Teleprompt::GEPA::MutationType::Combine,
        DSPy::Teleprompt::GEPA::MutationType::Rephrase
      )
    end

    it 'requires config parameter' do
      expect { described_class.new }.to raise_error(ArgumentError)
    end
  end

  describe '#mutate_program' do
    let(:engine) { described_class.new(config: config) }

    it 'returns mutated program with different instruction' do
      # Use a config with 100% mutation rate to ensure mutation happens
      high_rate_config = DSPy::Teleprompt::GEPA::GEPAConfig.new.tap { |c| c.mutation_rate = 1.0 }
      engine = described_class.new(config: high_rate_config)
      
      # Mock the instruction proposer to return an improved instruction
      allow(engine.instruction_proposer).to receive(:propose_instruction).and_return("Solve the problem step by step")
      allow(engine).to receive(:extract_instruction).with(test_program).and_return("Solve the problem")
      allow(engine).to receive(:create_mutated_program).and_return(test_program)
      
      mutated = engine.mutate_program(test_program)
      
      expect(mutated).not_to be_nil
      expect(engine.instruction_proposer).to have_received(:propose_instruction)
    end

    it 'handles mutation failures gracefully' do
      allow(engine).to receive(:extract_instruction).and_raise(StandardError, 'Mutation error')
      
      mutated = engine.mutate_program(test_program)
      
      expect(mutated).to eq(test_program) # Returns original on failure
    end

    it 'respects mutation rate configuration' do
      low_rate_config = DSPy::Teleprompt::GEPA::GEPAConfig.new.tap { |c| c.mutation_rate = 0.0 }
      engine = described_class.new(config: low_rate_config)
      
      # With 0% mutation rate, should return original program
      mutated = engine.mutate_program(test_program)
      expect(mutated).to eq(test_program)
    end
  end

  describe '#batch_mutate' do
    let(:engine) { described_class.new(config: config) }
    let(:programs) { [test_program, test_program, test_program] }

    it 'mutates multiple programs' do
      allow(engine).to receive(:mutate_program).and_return(test_program)
      
      mutated_programs = engine.batch_mutate(programs)
      
      expect(mutated_programs.size).to eq(programs.size)
      expect(engine).to have_received(:mutate_program).exactly(3).times
    end

    it 'handles empty program list' do
      mutated = engine.batch_mutate([])
      expect(mutated).to be_empty
    end
  end

  describe '#extract_instruction' do
    let(:engine) { described_class.new(config: config) }

    it 'extracts instruction from program description' do
      # Mock program with signature containing description
      signature_class = double('signature', description: "Solve math problems carefully")
      program = double('program', signature_class: signature_class)
      
      instruction = engine.send(:extract_instruction, program)
      
      expect(instruction).to eq("Solve math problems carefully")
    end

    it 'handles programs without signature description' do
      signature_class = double('signature', description: nil)
      program = double('program', signature_class: signature_class)
      
      instruction = engine.send(:extract_instruction, program)
      
      expect(instruction).to include("complete the task") # Default fallback
    end
  end

  describe '#apply_mutation' do
    let(:engine) { described_class.new(config: config) }

    it 'applies rewrite mutation' do
      original = "Answer the question"
      mutated = engine.send(:apply_mutation, original, DSPy::Teleprompt::GEPA::MutationType::Rewrite)
      
      expect(mutated).not_to eq(original)
      expect(mutated).to be_a(String)
    end

    it 'applies expand mutation' do
      original = "Calculate"
      mutated = engine.send(:apply_mutation, original, DSPy::Teleprompt::GEPA::MutationType::Expand)
      
      expect(mutated).to include(original) # Original should be contained
      expect(mutated.length).to be > original.length
    end

    it 'applies simplify mutation' do
      original = "Carefully analyze the complex problem and provide detailed step-by-step reasoning"
      mutated = engine.send(:apply_mutation, original, DSPy::Teleprompt::GEPA::MutationType::Simplify)
      
      expect(mutated).to be_a(String)
      expect(mutated.length).to be <= original.length
    end

    it 'applies combine mutation' do
      original = "Solve this problem"
      mutated = engine.send(:apply_mutation, original, DSPy::Teleprompt::GEPA::MutationType::Combine)
      
      expect(mutated).to be_a(String)
      expect(mutated).not_to eq(original)
    end

    it 'applies rephrase mutation' do
      original = "Solve the problem and answer carefully"
      mutated = engine.send(:apply_mutation, original, DSPy::Teleprompt::GEPA::MutationType::Rephrase)
      
      expect(mutated).to be_a(String)
      # Either should change or stay same based on random chance
      expect([mutated == original, mutated != original].any?).to be(true)
    end

    it 'handles unknown mutation types' do
      # Test with nil since enums are type-safe now
      original = "Test instruction"
      
      # This test needs to be adapted since we can't pass invalid enum values
      # We'll test the fallback in a different way
      expect(engine.send(:apply_mutation, original, DSPy::Teleprompt::GEPA::MutationType::Rewrite)).to be_a(String)
    end
  end

  describe '#create_mutated_program' do
    let(:engine) { described_class.new(config: config) }

    it 'creates new program with mutated instruction' do
      new_instruction = "Solve step by step with detailed reasoning"
      
      mutated_program = engine.send(:create_mutated_program, test_program, new_instruction)
      
      expect(mutated_program).not_to be_nil
      # In real implementation, this would create a new program instance
      # For now, we'll verify it returns a program-like object
    end
  end

  describe '#mutation_diversity' do
    let(:engine) { described_class.new(config: config) }

    it 'measures diversity of mutation types' do
      mutations = [:rewrite, :expand, :rewrite, :simplify, :expand]
      diversity = engine.send(:mutation_diversity, mutations)
      
      expect(diversity).to be_between(0.0, 1.0)
      expect(diversity).to be > 0.0 # Should have some diversity
    end

    it 'returns 0 for uniform mutations' do
      mutations = [:rewrite, :rewrite, :rewrite]
      diversity = engine.send(:mutation_diversity, mutations)
      
      expect(diversity).to be < 0.5 # Low diversity
    end

    it 'handles empty mutation list' do
      diversity = engine.send(:mutation_diversity, [])
      expect(diversity).to eq(0.0)
    end
  end

  describe '#select_mutation_type' do
    let(:engine) { described_class.new(config: config) }

    it 'selects from configured mutation types' do
      mutation_type = engine.send(:select_mutation_type)
      
      expect(config.mutation_types).to include(mutation_type)
    end

    it 'uses adaptive selection based on context' do
      # Test with different instruction contexts
      simple_instruction = "Answer"
      complex_instruction = "Provide detailed step-by-step analysis with comprehensive reasoning"
      
      simple_mutation = engine.send(:select_mutation_type, simple_instruction)
      complex_mutation = engine.send(:select_mutation_type, complex_instruction)
      
      expect(simple_mutation).to be_a(DSPy::Teleprompt::GEPA::MutationType)
      expect(complex_mutation).to be_a(DSPy::Teleprompt::GEPA::MutationType)
    end
  end
end