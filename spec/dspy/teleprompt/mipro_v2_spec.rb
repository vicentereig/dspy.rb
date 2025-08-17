require 'spec_helper'
require 'ostruct'
require 'dspy/teleprompt/mipro_v2'
require 'dspy/signature'
require 'dspy/predict'
require 'dspy/example'

# Test signature for MIPROv2 testing
class MIPROv2QA < DSPy::Signature
  description "Answer questions with detailed reasoning and analysis"

  input do
    const :question, String, description: "The question to answer"
    const :context, String, description: "Relevant context information"
  end

  output do
    const :answer, String, description: "The answer to the question"
    const :reasoning, String, description: "Step-by-step reasoning process"
    const :confidence, Float, description: "Confidence in the answer (0.0 to 1.0)"
  end
end

# Mock optimizable program for MIPROv2 testing
class MockMIPROProgram
  attr_reader :signature_class, :instruction, :few_shot_examples

  def initialize(signature_class, instruction: nil, few_shot_examples: [])
    @signature_class = signature_class
    @instruction = instruction || signature_class.description
    @few_shot_examples = few_shot_examples
  end

  def call(question:, context:)
    # Simulate improved performance with better configuration
    base_confidence = 0.6
    
    # Better performance with detailed instructions
    if @instruction&.include?("step") || @instruction&.include?("reasoning")
      base_confidence += 0.15
    end
    
    # Better performance with few-shot examples
    if @few_shot_examples.any?
      base_confidence += 0.1 * [@few_shot_examples.size, 3].min
    end
    
    # Add some variability
    final_confidence = [base_confidence + rand(0.2) - 0.1, 1.0].min
    
    # Generate response based on confidence
    if final_confidence > 0.8
      answer = "High quality answer based on context"
      reasoning = @instruction&.include?("step") ? "Step 1: Analyze context. Step 2: Extract key information. Step 3: Formulate answer." : "Based on the provided context."
    elsif final_confidence > 0.6
      answer = "Good answer with some uncertainty"
      reasoning = "Analyzed the context but some uncertainty remains."
    else
      answer = "Basic answer"
      reasoning = "Limited analysis possible."
    end
    
    OpenStruct.new(
      question: question,
      context: context,
      answer: answer,
      reasoning: reasoning,
      confidence: final_confidence
    )
  end

  def with_instruction(new_instruction)
    self.class.new(@signature_class, instruction: new_instruction, few_shot_examples: @few_shot_examples)
  end

  def with_examples(new_examples)
    self.class.new(@signature_class, instruction: @instruction, few_shot_examples: new_examples)
  end

  def prompt
    OpenStruct.new(instruction: @instruction)
  end

  def to_h
    { answer: @answer, reasoning: @reasoning, confidence: @confidence }
  end
end

RSpec.describe DSPy::Teleprompt::MIPROv2 do
  let(:test_program) { MockMIPROProgram.new(MIPROv2QA) }
  
  let(:training_examples) do
    [
      DSPy::Example.new(
        signature_class: MIPROv2QA,
        input: { 
          question: "What causes photosynthesis?",
          context: "Plants use sunlight, water, and carbon dioxide to produce glucose and oxygen through chlorophyll."
        },
        expected: { 
          answer: "Photosynthesis is caused by plants using sunlight, water, and CO2 to make glucose.",
          reasoning: "The process requires chlorophyll to capture light energy and convert it to chemical energy.",
          confidence: 0.9
        },
        id: "qa_1"
      ),
      DSPy::Example.new(
        signature_class: MIPROv2QA,
        input: { 
          question: "How do birds fly?",
          context: "Birds have hollow bones, powerful flight muscles, and wing shapes that create lift through air pressure differences."
        },
        expected: { 
          answer: "Birds fly by using their wings to generate lift through air pressure differences.",
          reasoning: "Hollow bones reduce weight while powerful muscles and wing shape create the necessary lift and thrust.",
          confidence: 0.85
        },
        id: "qa_2"
      ),
      DSPy::Example.new(
        signature_class: MIPROv2QA,
        input: { 
          question: "What makes water boil?",
          context: "Water boils when heated to 100°C at sea level, as thermal energy overcomes intermolecular forces."
        },
        expected: { 
          answer: "Water boils when thermal energy overcomes the intermolecular forces holding water molecules together.",
          reasoning: "At 100°C at sea level, molecules have enough energy to transition from liquid to gas phase.",
          confidence: 0.95
        },
        id: "qa_3"
      ),
      DSPy::Example.new(
        signature_class: MIPROv2QA,
        input: { 
          question: "Why is the sky blue?",
          context: "Light scattering in Earth's atmosphere affects different wavelengths differently due to particle size."
        },
        expected: { 
          answer: "The sky appears blue due to Rayleigh scattering of shorter blue wavelengths in the atmosphere.",
          reasoning: "Shorter wavelengths scatter more than longer ones when interacting with atmospheric particles.",
          confidence: 0.88
        },
        id: "qa_4"
      ),
      DSPy::Example.new(
        signature_class: MIPROv2QA,
        input: { 
          question: "How does gravity work?",
          context: "Gravity is a fundamental force that attracts objects with mass toward each other according to Einstein's general relativity."
        },
        expected: { 
          answer: "Gravity works by warping spacetime around massive objects, causing other objects to follow curved paths.",
          reasoning: "According to general relativity, mass curves spacetime, and objects follow the straightest path in this curved space.",
          confidence: 0.82
        },
        id: "qa_5"
      )
    ]
  end

  let(:validation_examples) do
    training_examples.take(2)
  end

  describe DSPy::Teleprompt::MIPROv2::AutoMode do
    it 'creates light mode configuration' do
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.light

      expect(mipro.mipro_config.num_trials).to eq(6)
      expect(mipro.mipro_config.num_instruction_candidates).to eq(3)
      expect(mipro.mipro_config.max_bootstrapped_examples).to eq(2)
      expect(mipro.mipro_config.optimization_strategy).to eq("greedy")
      expect(mipro.mipro_config.early_stopping_patience).to eq(2)
    end

    it 'creates medium mode configuration' do
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.medium

      expect(mipro.mipro_config.num_trials).to eq(12)
      expect(mipro.mipro_config.num_instruction_candidates).to eq(5)
      expect(mipro.mipro_config.max_bootstrapped_examples).to eq(4)
      expect(mipro.mipro_config.optimization_strategy).to eq("adaptive")
      expect(mipro.mipro_config.early_stopping_patience).to eq(3)
    end

    it 'creates heavy mode configuration' do
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.heavy

      expect(mipro.mipro_config.num_trials).to eq(18)
      expect(mipro.mipro_config.num_instruction_candidates).to eq(8)
      expect(mipro.mipro_config.max_bootstrapped_examples).to eq(6)
      expect(mipro.mipro_config.optimization_strategy).to eq("bayesian")
      expect(mipro.mipro_config.early_stopping_patience).to eq(5)
    end

    it 'accepts metric parameter for light mode' do
      custom_metric = proc { |example, prediction| true }
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.light(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
      expect(mipro.mipro_config.num_trials).to eq(6)
      expect(mipro.mipro_config.optimization_strategy).to eq("greedy")
    end

    it 'accepts metric parameter for medium mode' do
      custom_metric = proc { |example, prediction| prediction[:confidence] > 0.8 }
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.medium(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
      expect(mipro.mipro_config.num_trials).to eq(12)
      expect(mipro.mipro_config.optimization_strategy).to eq("adaptive")
    end

    it 'accepts metric parameter for heavy mode' do
      custom_metric = proc { |example, prediction| prediction[:answer].length > 10 }
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.heavy(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
      expect(mipro.mipro_config.num_trials).to eq(18)
      expect(mipro.mipro_config.optimization_strategy).to eq("bayesian")
    end
  end

  describe DSPy::Teleprompt::MIPROv2::MIPROv2Config do
    it 'has sensible defaults' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new

      expect(config.num_trials).to eq(12)
      expect(config.num_instruction_candidates).to eq(5)
      expect(config.bootstrap_sets).to eq(5)
      expect(config.optimization_strategy).to eq("adaptive")
      expect(config.init_temperature).to eq(1.0)
      expect(config.final_temperature).to eq(0.1)
      expect(config.early_stopping_patience).to eq(3)
      expect(config.use_bayesian_optimization).to be(true)
      expect(config.track_diversity).to be(true)
      expect(config.proposer_config).to be_a(DSPy::Propose::GroundedProposer::Config)
    end

    it 'allows configuration customization' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.num_trials = 8
      config.optimization_strategy = "greedy"
      config.init_temperature = 0.5

      expect(config.num_trials).to eq(8)
      expect(config.optimization_strategy).to eq("greedy")
      expect(config.init_temperature).to eq(0.5)
    end

    it 'serializes to hash correctly' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      hash = config.to_h

      expect(hash).to include(:num_trials, :optimization_strategy, :init_temperature)
      expect(hash[:num_trials]).to eq(12)
      expect(hash[:optimization_strategy]).to eq("adaptive")
    end
  end

  describe DSPy::Teleprompt::MIPROv2::CandidateConfig do
    let(:candidate) do
      DSPy::Teleprompt::MIPROv2::CandidateConfig.new(
        instruction: "Analyze step by step",
        few_shot_examples: training_examples.take(2),
        metadata: { type: "combined", rank: 1 }
      )
    end

    it 'stores candidate configuration correctly' do
      expect(candidate.instruction).to eq("Analyze step by step")
      expect(candidate.few_shot_examples.size).to eq(2)
      expect(candidate.metadata[:type]).to eq("combined")
      expect(candidate.config_id).to be_a(String)
      expect(candidate.config_id.length).to eq(12)
    end

    it 'generates consistent config IDs' do
      candidate2 = DSPy::Teleprompt::MIPROv2::CandidateConfig.new(
        instruction: "Analyze step by step",
        few_shot_examples: training_examples.take(2),
        metadata: { type: "combined", rank: 1 }
      )

      expect(candidate.config_id).to eq(candidate2.config_id)
    end

    it 'serializes to hash' do
      hash = candidate.to_h

      expect(hash).to include(:instruction, :few_shot_examples, :metadata, :config_id)
      expect(hash[:few_shot_examples]).to eq(2) # Count, not actual examples
    end

    it 'freezes metadata' do
      expect(candidate.metadata).to be_frozen
    end
  end

  describe DSPy::Teleprompt::MIPROv2::MIPROv2Result do
    let(:mock_candidates) do
      [
        DSPy::Teleprompt::MIPROv2::CandidateConfig.new(
          instruction: "Test instruction",
          few_shot_examples: [],
          metadata: { type: "instruction_only" }
        )
      ]
    end

    let(:result) do
      DSPy::Teleprompt::MIPROv2::MIPROv2Result.new(
        optimized_program: test_program,
        scores: { pass_rate: 0.85 },
        history: { total_trials: 5 },
        best_score_name: "pass_rate",
        best_score_value: 0.85,
        metadata: { optimizer: "MIPROv2" },
        evaluated_candidates: mock_candidates,
        optimization_trace: { temperature_history: [1.0, 0.8, 0.6] },
        bootstrap_statistics: { success_rate: 0.8 },
        proposal_statistics: { num_candidates: 5 }
      )
    end

    it 'stores MIPROv2-specific results correctly' do
      expect(result.evaluated_candidates).to eq(mock_candidates)
      expect(result.optimization_trace[:temperature_history]).to eq([1.0, 0.8, 0.6])
      expect(result.bootstrap_statistics[:success_rate]).to eq(0.8)
      expect(result.proposal_statistics[:num_candidates]).to eq(5)
    end

    it 'inherits from OptimizationResult' do
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).to eq(test_program)
      expect(result.best_score_value).to eq(0.85)
    end

    it 'serializes to hash with MIPROv2 extensions' do
      hash = result.to_h

      expect(hash).to include(:evaluated_candidates, :optimization_trace, :bootstrap_statistics, :proposal_statistics)
      expect(hash[:evaluated_candidates]).to be_an(Array)
      expect(hash[:evaluated_candidates].first).to include(:instruction, :config_id)
    end

    it 'freezes MIPROv2-specific data structures' do
      expect(result.evaluated_candidates).to be_frozen
      expect(result.optimization_trace).to be_frozen
      expect(result.bootstrap_statistics).to be_frozen
      expect(result.proposal_statistics).to be_frozen
    end
  end

  describe '#initialize' do
    it 'creates MIPROv2 with default configuration' do
      mipro = DSPy::Teleprompt::MIPROv2.new

      expect(mipro.mipro_config).to be_a(DSPy::Teleprompt::MIPROv2::MIPROv2Config)
      expect(mipro.proposer).to be_a(DSPy::Propose::GroundedProposer)
    end

    it 'creates MIPROv2 with custom configuration' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.num_trials = 5
      
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

      expect(mipro.mipro_config).to eq(config)
      expect(mipro.mipro_config.num_trials).to eq(5)
    end

    it 'accepts custom metric' do
      custom_metric = proc { |example, prediction| true }
      mipro = DSPy::Teleprompt::MIPROv2.new(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
    end
  end

  describe '#compile' do
    before do
      # Mock the grounded proposer to return predictable instructions
      allow_any_instance_of(DSPy::Propose::GroundedProposer).to receive(:propose_instructions).and_return(
        DSPy::Propose::GroundedProposer::ProposalResult.new(
          candidate_instructions: [
            "Analyze the question and context step by step to provide a comprehensive answer with detailed reasoning",
            "Examine the provided context carefully and extract key information to formulate a well-reasoned response",
            "Think through the problem systematically, using the context to support your analysis and conclusion"
          ],
          analysis: { 
            complexity_indicators: { requires_reasoning: true },
            common_themes: ["question_answering", "analytical_reasoning"]
          },
          metadata: { model: "test", generation_timestamp: Time.now.iso8601 }
        )
      )

      # Mock bootstrap to return some examples
      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return(
        DSPy::Teleprompt::Utils::BootstrapResult.new(
          candidate_sets: [
            training_examples.take(2),
            training_examples.drop(1).take(2),
            training_examples.drop(2).take(2)
          ],
          successful_examples: training_examples.take(4),
          failed_examples: [training_examples.last],
          statistics: { 
            success_rate: 0.8, 
            successful_count: 4, 
            failed_count: 1,
            candidate_sets_created: 3
          }
        )
      )
    end

    it 'performs end-to-end MIPROv2 optimization' do
      # Use light mode for faster testing
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.num_trials = 3
      config.num_instruction_candidates = 2
      config.bootstrap_sets = 2
      
      # Use a custom metric that simulates successful evaluations
      # based on the mock program's confidence score
      custom_metric = proc do |example, prediction|
        if prediction && prediction.respond_to?(:confidence)
          prediction.confidence > 0.7  # Consider high confidence as success
        else
          false
        end
      end
      
      mipro = DSPy::Teleprompt::MIPROv2.new(metric: custom_metric, config: config)
      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result).to be_a(DSPy::Teleprompt::MIPROv2::MIPROv2Result)
      expect(result.optimized_program).not_to be_nil
      expect(result.scores).to include(:pass_rate)
      expect(result.best_score_value).to be_a(Float)
      expect(result.best_score_value).to be >= 0.0

      # MIPROv2-specific checks
      expect(result.evaluated_candidates).to be_an(Array)
      expect(result.bootstrap_statistics).to include(:success_rate)
      expect(result.proposal_statistics).to include(:common_themes)
      expect(result.metadata[:optimizer]).to eq("MIPROv2")
    end

    it 'validates inputs before optimization' do
      mipro = DSPy::Teleprompt::MIPROv2.new

      expect {
        mipro.compile(nil, trainset: training_examples)
      }.to raise_error(ArgumentError, /Program cannot be nil/)

      expect {
        mipro.compile(test_program, trainset: [])
      }.to raise_error(ArgumentError, /Training set cannot be empty/)
    end

    it 'handles missing validation set' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.require_validation_examples = false
      config.num_trials = 2
      
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)
      result = mipro.compile(test_program, trainset: training_examples)

      expect(result).to be_a(DSPy::Teleprompt::MIPROv2::MIPROv2Result)
    end

    it 'respects trial limit configuration' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.num_trials = 2
      
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)
      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result.history[:total_trials]).to be <= 2
    end

    it 'tracks optimization phases' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.num_trials = 2
      
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

      # Expect phase events to be emitted (allow other events too)
      expect(mipro).to receive(:emit_event).with('phase_start', { phase: 1, name: 'bootstrap' }).and_call_original
      expect(mipro).to receive(:emit_event).with('phase_complete', hash_including(phase: 1)).and_call_original
      expect(mipro).to receive(:emit_event).with('phase_start', { phase: 2, name: 'instruction_proposal' }).and_call_original
      expect(mipro).to receive(:emit_event).with('phase_complete', hash_including(phase: 2)).and_call_original
      expect(mipro).to receive(:emit_event).with('phase_start', { phase: 3, name: 'optimization' }).and_call_original
      expect(mipro).to receive(:emit_event).with('phase_complete', hash_including(phase: 3)).and_call_original
      
      # Allow any other events to be emitted
      allow(mipro).to receive(:emit_event).and_call_original

      mipro.compile(test_program, trainset: training_examples, valset: validation_examples)
    end
  end

  describe 'optimization strategies' do
    let(:mock_candidates) do
      [
        DSPy::Teleprompt::MIPROv2::CandidateConfig.new(
          instruction: "Instruction 1",
          few_shot_examples: [],
          metadata: { type: "instruction_only", rank: 0 }
        ),
        DSPy::Teleprompt::MIPROv2::CandidateConfig.new(
          instruction: "Instruction 2",
          few_shot_examples: training_examples.take(1),
          metadata: { type: "combined", rank: 1 }
        )
      ]
    end

    let(:optimization_state) do
      {
        candidates: mock_candidates,
        scores: { mock_candidates.first.config_id => 0.7 },
        exploration_counts: Hash.new(0),
        temperature: 0.5,
        best_score_history: [0.6, 0.7],
        diversity_scores: {},
        no_improvement_count: 0
      }
    end

    describe 'greedy selection' do
      it 'prioritizes unexplored candidates' do
        config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
        config.optimization_strategy = "greedy"
        mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

        selected = mipro.send(:select_candidate_greedy, mock_candidates, optimization_state)
        
        # Should select the unexplored candidate (second one)
        expect(selected).to eq(mock_candidates[1])
      end

      it 'selects highest scoring when all explored' do
        config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
        config.optimization_strategy = "greedy"
        mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

        # Mark both as explored
        state_with_all_explored = optimization_state.dup
        state_with_all_explored[:scores][mock_candidates[1].config_id] = 0.6

        selected = mipro.send(:select_candidate_greedy, mock_candidates, state_with_all_explored)
        
        # Should select the higher scoring candidate (first one: 0.7 > 0.6)
        expect(selected).to eq(mock_candidates[0])
      end
    end

    describe 'adaptive selection' do
      it 'balances exploration and exploitation' do
        config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
        config.optimization_strategy = "adaptive"
        mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

        selected = mipro.send(:select_candidate_adaptive, mock_candidates, optimization_state, 5)
        
        expect(mock_candidates).to include(selected)
        # Temperature should be updated based on progress
        expect(optimization_state[:temperature]).to be < 1.0
      end
    end

    describe 'bayesian selection' do
      it 'uses adaptive selection as fallback' do
        config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
        config.optimization_strategy = "bayesian"
        mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

        selected = mipro.send(:select_candidate_bayesian, mock_candidates, optimization_state, 5)
        
        expect(mock_candidates).to include(selected)
      end
    end
  end

  describe 'early stopping' do
    it 'stops when no improvement for patience trials' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.early_stopping_patience = 2
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

      state_no_improvement = {
        no_improvement_count: 2,
        best_score_history: [0.7, 0.7, 0.7]
      }

      should_stop = mipro.send(:should_early_stop?, state_no_improvement, 5)
      expect(should_stop).to be(true)
    end

    it 'continues when improvement is happening' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.early_stopping_patience = 2
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

      state_with_improvement = {
        no_improvement_count: 0,
        best_score_history: [0.6, 0.7, 0.8]
      }

      should_stop = mipro.send(:should_early_stop?, state_with_improvement, 5)
      expect(should_stop).to be(false)
    end

    it 'does not stop too early' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.early_stopping_patience = 3
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

      state_early_trial = { no_improvement_count: 5 }

      should_stop = mipro.send(:should_early_stop?, state_early_trial, 1) # Trial 1
      expect(should_stop).to be(false)
    end
  end

  describe 'helper methods' do
    it 'extracts current instruction from program' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      instruction = mipro.send(:extract_current_instruction, test_program)
      
      expect(instruction).to eq(test_program.instruction)
    end

    it 'extracts signature class from program' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      signature_class = mipro.send(:extract_signature_class, test_program)
      
      expect(signature_class).to eq(MIPROv2QA)
    end

    it 'calculates diversity score' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      
      candidate = DSPy::Teleprompt::MIPROv2::CandidateConfig.new(
        instruction: "A" * 100, # Length 100
        few_shot_examples: training_examples.take(3),
        metadata: {}
      )
      
      diversity = mipro.send(:calculate_diversity_score, candidate)
      
      expect(diversity).to be_a(Float)
      expect(diversity).to be >= 0.0
      expect(diversity).to be <= 1.0
    end

    it 'infers auto mode correctly' do
      light_config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      light_config.num_trials = 5
      light_mipro = DSPy::Teleprompt::MIPROv2.new(config: light_config)
      
      medium_config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      medium_config.num_trials = 10
      medium_mipro = DSPy::Teleprompt::MIPROv2.new(config: medium_config)
      
      heavy_config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      heavy_config.num_trials = 20
      heavy_mipro = DSPy::Teleprompt::MIPROv2.new(config: heavy_config)

      expect(light_mipro.send(:infer_auto_mode)).to eq("light")
      expect(medium_mipro.send(:infer_auto_mode)).to eq("medium")
      expect(heavy_mipro.send(:infer_auto_mode)).to eq("heavy")
    end
  end

  describe 'compilation with mocked components' do
    it 'works with mocked components' do
      config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
      config.num_trials = 1
      mipro = DSPy::Teleprompt::MIPROv2.new(config: config)

      # Mock components to avoid complex setup
      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return(
        DSPy::Teleprompt::Utils::BootstrapResult.new(
          candidate_sets: [training_examples.take(1)],
          successful_examples: training_examples.take(2),
          failed_examples: [],
          statistics: { success_rate: 1.0 }
        )
      )
      
      allow_any_instance_of(DSPy::Propose::GroundedProposer).to receive(:propose_instructions).and_return(
        DSPy::Propose::GroundedProposer::ProposalResult.new(
          candidate_instructions: ["Test instruction"],
          analysis: {},
          metadata: {}
        )
      )

      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)
      expect(result).to be_a(DSPy::Teleprompt::MIPROv2::MIPROv2Result)
    end
  end

  private

  def create_test_example(question, answer, reasoning = "Test reasoning")
    DSPy::Example.new(
      signature_class: MIPROv2QA,
      input: { question: question, context: "Test context" },
      expected: { answer: answer, reasoning: reasoning, confidence: 0.8 },
      id: "test_#{question.gsub(/\W/, '_').downcase}"
    )
  end
end