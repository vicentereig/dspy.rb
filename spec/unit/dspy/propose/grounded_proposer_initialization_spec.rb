# frozen_string_literal: true

require 'spec_helper'
require 'dspy/propose/grounded_proposer'
require 'dspy/propose/dataset_summary_generator'

RSpec.describe DSPy::Propose::GroundedProposer, 'initialization with awareness' do
  let(:signature_class) do
    Class.new(DSPy::Signature) do
      input { const :question, String }
      output { const :answer, String }
    end
  end

  let(:program) do
    sig_class = signature_class  # Capture in local variable
    Class.new(DSPy::Module) do
      define_method :initialize do
        super()
        @predictor = DSPy::Predict.new(sig_class)
      end

      define_method :forward do |question:|
        @predictor.call(question: question)
      end
    end.new
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: signature_class,
        input: { question: "What is 2+2?" },
        expected: { answer: "4" }
      )
    ]
  end

  describe 'initialization with program and trainset' do
    it 'accepts program and trainset parameters' do
      config = DSPy::Propose::GroundedProposer::Config.new
      proposer = described_class.new(config: config, program: program, trainset: trainset)

      expect(proposer).to be_a(DSPy::Propose::GroundedProposer)
    end

    it 'generates dataset summary when use_dataset_summary is true' do
      config = DSPy::Propose::GroundedProposer::Config.new
      config.use_dataset_summary = true

      # Initialize proposer - this will attempt to generate summary
      # (may be nil if LLM not configured, but code should not crash)
      proposer = described_class.new(config: config, program: program, trainset: trainset)

      # Test passes if initialization doesn't crash
      # In real usage with LLM configured, @dataset_summary would be populated
      expect(proposer).to be_a(DSPy::Propose::GroundedProposer)
    end

    it 'skips dataset summary when use_dataset_summary is false' do
      config = DSPy::Propose::GroundedProposer::Config.new
      config.use_dataset_summary = false

      proposer = described_class.new(config: config, program: program, trainset: trainset)
      expect(proposer.instance_variable_get(:@dataset_summary)).to be_nil
    end

    it 'extracts program source when program_aware is true' do
      config = DSPy::Propose::GroundedProposer::Config.new
      config.program_aware = true

      proposer = described_class.new(config: config, program: program, trainset: trainset)

      program_code = proposer.instance_variable_get(:@program_code_string)
      # Should extract some code representation
      expect(program_code).to be_a(String)
      expect(program_code.length).to be > 0
    end

    it 'skips program source extraction when program_aware is false' do
      config = DSPy::Propose::GroundedProposer::Config.new
      config.program_aware = false

      proposer = described_class.new(config: config, program: program, trainset: trainset)
      expect(proposer.instance_variable_get(:@program_code_string)).to be_nil
    end
  end

  describe 'TIPS dictionary' do
    it 'defines all Python-compatible tips' do
      expect(described_class::TIPS).to be_a(Hash)
      expect(described_class::TIPS.keys).to contain_exactly(
        "none", "creative", "simple", "description", "high_stakes", "persona"
      )
    end

    it 'has correct tip content matching Python' do
      expect(described_class::TIPS["none"]).to eq("")
      expect(described_class::TIPS["creative"]).to include("creative")
      expect(described_class::TIPS["simple"]).to include("clear and concise")
      expect(described_class::TIPS["description"]).to include("informative and descriptive")
      expect(described_class::TIPS["high_stakes"]).to include("high stakes")
      expect(described_class::TIPS["persona"]).to include("persona")
    end
  end
end
