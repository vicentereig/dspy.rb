# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Module, '#configure LM propagation' do
  let(:global_lm) { instance_double(DSPy::LM, 'global_lm') }
  let(:instance_lm) { instance_double(DSPy::LM, 'instance_lm') }
  let(:child_lm) { instance_double(DSPy::LM, 'child_lm') }

  before do
    allow(global_lm).to receive(:is_a?).with(DSPy::LM).and_return(true)
    allow(instance_lm).to receive(:is_a?).with(DSPy::LM).and_return(true)
    allow(child_lm).to receive(:is_a?).with(DSPy::LM).and_return(true)

    [global_lm, instance_lm, child_lm].each do |lm|
      allow(lm).to receive(:schema_format).and_return(:json)
      allow(lm).to receive(:data_format).and_return(:json)
    end
  end

  # Simple test signature for creating predictors
  let(:test_signature) do
    Class.new(DSPy::Signature) do
      description "Test signature"
      input { const :question, String }
      output { const :answer, String }
    end
  end

  # Simple tool for ReAct tests
  let(:test_tool) { SorbetAddNumbers.new }

  describe 'propagation to child predictors' do
    context 'with DSPy::ReAct' do
      let(:react_agent) { DSPy::ReAct.new(test_signature, tools: [test_tool], max_iterations: 1) }

      it 'propagates LM to thought_generator' do
        react_agent.configure { |c| c.lm = instance_lm }

        thought_gen = react_agent.named_predictors.find { |name, _| name == 'thought_generator' }&.last
        expect(thought_gen.config.lm).to eq(instance_lm)
      end

      it 'propagates LM to observation_processor' do
        react_agent.configure { |c| c.lm = instance_lm }

        obs_proc = react_agent.named_predictors.find { |name, _| name == 'observation_processor' }&.last
        expect(obs_proc.config.lm).to eq(instance_lm)
      end

      it 'propagates to all predictors at once' do
        react_agent.configure { |c| c.lm = instance_lm }

        react_agent.predictors.each do |predictor|
          expect(predictor.config.lm).to eq(instance_lm)
        end
      end
    end

    context 'with DSPy::CodeAct' do
      let(:codeact_agent) { DSPy::CodeAct.new(test_signature, max_iterations: 1) }

      it 'propagates LM to code_generator' do
        codeact_agent.configure { |c| c.lm = instance_lm }

        code_gen = codeact_agent.named_predictors.find { |name, _| name == 'code_generator' }&.last
        expect(code_gen.config.lm).to eq(instance_lm)
      end

      it 'propagates LM to observation_processor' do
        codeact_agent.configure { |c| c.lm = instance_lm }

        obs_proc = codeact_agent.named_predictors.find { |name, _| name == 'observation_processor' }&.last
        expect(obs_proc.config.lm).to eq(instance_lm)
      end
    end
  end

  describe 'self-reference handling' do
    context 'with DSPy::Predict (returns self in named_predictors)' do
      let(:predictor) { DSPy::Predict.new(test_signature) }

      it 'does not cause infinite recursion' do
        expect { predictor.configure { |c| c.lm = instance_lm } }.not_to raise_error
      end

      it 'sets LM on the predictor itself' do
        predictor.configure { |c| c.lm = instance_lm }
        expect(predictor.config.lm).to eq(instance_lm)
      end
    end
  end

  describe 'respecting explicit child configuration' do
    let(:react_agent) { DSPy::ReAct.new(test_signature, tools: [test_tool], max_iterations: 1) }

    it 'does not overwrite explicitly configured child LMs' do
      # First configure the child directly
      thought_gen = react_agent.named_predictors.find { |name, _| name == 'thought_generator' }&.last
      thought_gen.configure { |c| c.lm = child_lm }

      # Then configure the parent
      react_agent.configure { |c| c.lm = instance_lm }

      # Child should retain its explicit configuration
      expect(thought_gen.config.lm).to eq(child_lm)
    end

    it 'propagates to children without explicit LM' do
      # Configure thought_generator explicitly
      thought_gen = react_agent.named_predictors.find { |name, _| name == 'thought_generator' }&.last
      thought_gen.configure { |c| c.lm = child_lm }

      # Configure parent
      react_agent.configure { |c| c.lm = instance_lm }

      # observation_processor should get parent's LM (no explicit config)
      obs_proc = react_agent.named_predictors.find { |name, _| name == 'observation_processor' }&.last
      expect(obs_proc.config.lm).to eq(instance_lm)
    end
  end

  describe '#configure_predictor' do
    let(:react_agent) { DSPy::ReAct.new(test_signature, tools: [test_tool], max_iterations: 1) }

    it 'configures specific predictor by name' do
      react_agent.configure_predictor('thought_generator') { |c| c.lm = child_lm }

      thought_gen = react_agent.named_predictors.find { |name, _| name == 'thought_generator' }&.last
      expect(thought_gen.config.lm).to eq(child_lm)
    end

    it 'raises ArgumentError for unknown predictor name' do
      expect {
        react_agent.configure_predictor('nonexistent') { |c| c.lm = child_lm }
      }.to raise_error(ArgumentError, /Unknown predictor: nonexistent/)
    end

    it 'includes available predictor names in error message' do
      expect {
        react_agent.configure_predictor('nonexistent') { |c| c.lm = child_lm }
      }.to raise_error(ArgumentError, /thought_generator.*observation_processor|observation_processor.*thought_generator/)
    end

    it 'returns self for method chaining' do
      result = react_agent.configure_predictor('thought_generator') { |c| c.lm = child_lm }
      expect(result).to eq(react_agent)
    end
  end

  describe 'method chaining' do
    let(:react_agent) { DSPy::ReAct.new(test_signature, tools: [test_tool], max_iterations: 1) }

    it 'supports configure followed by configure_predictor' do
      react_agent
        .configure { |c| c.lm = instance_lm }
        .configure_predictor('thought_generator') { |c| c.lm = child_lm }

      thought_gen = react_agent.named_predictors.find { |name, _| name == 'thought_generator' }&.last
      obs_proc = react_agent.named_predictors.find { |name, _| name == 'observation_processor' }&.last

      expect(thought_gen.config.lm).to eq(child_lm)
      expect(obs_proc.config.lm).to eq(instance_lm)
    end
  end

  describe 'recursive propagation' do
    # Create a nested module structure for testing
    let(:nested_module_class) do
      test_sig = test_signature

      Class.new(DSPy::Module) do
        define_method(:initialize) do
          super()
          @inner_agent = DSPy::ReAct.new(test_sig, tools: [SorbetAddNumbers.new], max_iterations: 1)
        end

        define_method(:named_predictors) do
          [['inner_agent', @inner_agent]]
        end

        define_method(:forward_untyped) do |**kwargs|
          kwargs
        end
      end
    end

    it 'propagates LM recursively to grandchildren' do
      outer_module = nested_module_class.new
      outer_module.configure { |c| c.lm = instance_lm }

      # Check inner agent got the LM
      inner_agent = outer_module.named_predictors.find { |name, _| name == 'inner_agent' }&.last
      expect(inner_agent.config.lm).to eq(instance_lm)

      # Check grandchildren (inner agent's predictors) got the LM
      inner_agent.predictors.each do |predictor|
        expect(predictor.config.lm).to eq(instance_lm)
      end
    end
  end

  describe 'configure returns self' do
    let(:predictor) { DSPy::Predict.new(test_signature) }

    it 'returns self for method chaining' do
      result = predictor.configure { |c| c.lm = instance_lm }
      expect(result).to eq(predictor)
    end
  end
end
