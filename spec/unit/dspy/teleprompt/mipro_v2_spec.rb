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

  # Helper method to create EvaluatedCandidate with new Data class
  def create_test_evaluated_candidate(instruction: "", few_shot_examples: [], type: DSPy::Teleprompt::CandidateType::Baseline, metadata: {})
    DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
      instruction: instruction,
      few_shot_examples: few_shot_examples,
      type: type,
      metadata: metadata,
      config_id: "test_#{SecureRandom.hex(6)}"
    )
  end
  
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

      expect(mipro.config.num_trials).to eq(6)
      expect(mipro.config.num_instruction_candidates).to eq(3)
      expect(mipro.config.max_bootstrapped_examples).to eq(2)
      expect(mipro.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Greedy)
      expect(mipro.config.early_stopping_patience).to eq(2)
    end

    it 'creates medium mode configuration' do
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.medium

      expect(mipro.config.num_trials).to eq(12)
      expect(mipro.config.num_instruction_candidates).to eq(5)
      expect(mipro.config.max_bootstrapped_examples).to eq(4)
      expect(mipro.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Adaptive)
      expect(mipro.config.early_stopping_patience).to eq(3)
    end

    it 'creates heavy mode configuration' do
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.heavy

      expect(mipro.config.num_trials).to eq(18)
      expect(mipro.config.num_instruction_candidates).to eq(8)
      expect(mipro.config.max_bootstrapped_examples).to eq(6)
      expect(mipro.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
      expect(mipro.config.early_stopping_patience).to eq(5)
    end

    it 'accepts metric parameter for light mode' do
      custom_metric = proc { |example, prediction| true }
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.light(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
      expect(mipro.config.num_trials).to eq(6)
      expect(mipro.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Greedy)
    end

    it 'accepts metric parameter for medium mode' do
      custom_metric = proc { |example, prediction| prediction[:confidence] > 0.8 }
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.medium(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
      expect(mipro.config.num_trials).to eq(12)
      expect(mipro.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Adaptive)
    end

    it 'accepts metric parameter for heavy mode' do
      custom_metric = proc { |example, prediction| prediction[:answer].length > 10 }
      mipro = DSPy::Teleprompt::MIPROv2::AutoMode.heavy(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
      expect(mipro.config.num_trials).to eq(18)
      expect(mipro.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
    end
  end


  # TODO: Removed old CandidateConfig tests - replaced with EvaluatedCandidate Data class

  describe DSPy::Teleprompt::MIPROv2::MIPROv2Result do
    let(:mock_candidates) do
      [
        create_test_evaluated_candidate(
          instruction: "Test instruction",
          few_shot_examples: [],
          type: DSPy::Teleprompt::CandidateType::InstructionOnly,
          metadata: {}
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

    it 'handles nil best_evaluation_result' do
      expect(result.best_evaluation_result).to be_nil
    end

    context 'with best_evaluation_result' do
      let(:mock_evaluation_result) do
        mock_results = [
          DSPy::Evaluate::EvaluationResult.new(
            example: training_examples.first,
            prediction: OpenStruct.new(answer: "Test answer", confidence: 0.9),
            trace: nil,
            metrics: { passed: true, confidence_score: 0.9, answer_length: 11 },
            passed: true
          ),
          DSPy::Evaluate::EvaluationResult.new(
            example: training_examples.last,
            prediction: OpenStruct.new(answer: "Another answer", confidence: 0.7),
            trace: nil,
            metrics: { passed: true, confidence_score: 0.7, answer_length: 14 },
            passed: true
          )
        ]
        
        DSPy::Evaluate::BatchEvaluationResult.new(
          results: mock_results,
          aggregated_metrics: { avg_confidence: 0.8, avg_length: 12.5 }
        )
      end

      let(:result_with_evaluation) do
        DSPy::Teleprompt::MIPROv2::MIPROv2Result.new(
          optimized_program: test_program,
          scores: { pass_rate: 1.0 },
          history: { total_trials: 3 },
          best_score_name: "pass_rate",
          best_score_value: 1.0,
          metadata: { optimizer: "MIPROv2" },
          evaluated_candidates: mock_candidates,
          optimization_trace: { temperature_history: [1.0, 0.5] },
          bootstrap_statistics: { success_rate: 1.0 },
          proposal_statistics: { num_candidates: 3 },
          best_evaluation_result: mock_evaluation_result
        )
      end

      it 'stores best_evaluation_result correctly' do
        expect(result_with_evaluation.best_evaluation_result).to eq(mock_evaluation_result)
        expect(result_with_evaluation.best_evaluation_result).to be_frozen
      end

      it 'provides access to detailed evaluation metrics' do
        eval_result = result_with_evaluation.best_evaluation_result
        
        expect(eval_result.total_examples).to eq(2)
        expect(eval_result.passed_examples).to eq(2)
        expect(eval_result.pass_rate).to eq(1.0)
        expect(eval_result.aggregated_metrics[:avg_confidence]).to eq(0.8)
      end

      it 'provides access to individual example results' do
        eval_result = result_with_evaluation.best_evaluation_result
        individual_results = eval_result.results
        
        expect(individual_results.length).to eq(2)
        
        first_result = individual_results.first
        expect(first_result.passed).to be(true)
        expect(first_result.metrics[:confidence_score]).to eq(0.9)
        expect(first_result.metrics[:answer_length]).to eq(11)
        expect(first_result.prediction.answer).to eq("Test answer")
      end

      it 'includes best_evaluation_result in hash serialization' do
        hash = result_with_evaluation.to_h
        
        expect(hash).to include(:best_evaluation_result)
        expect(hash[:best_evaluation_result]).to be_a(Hash)
        expect(hash[:best_evaluation_result]).to include(:total_examples, :pass_rate, :results)
        expect(hash[:best_evaluation_result][:total_examples]).to eq(2)
        expect(hash[:best_evaluation_result][:pass_rate]).to eq(1.0)
      end

      it 'handles hash serialization when best_evaluation_result is nil' do
        hash = result.to_h
        
        expect(hash).to include(:best_evaluation_result)
        expect(hash[:best_evaluation_result]).to be_nil
      end
    end
  end

  describe '#initialize' do
    it 'creates MIPROv2 with default configuration' do
      mipro = DSPy::Teleprompt::MIPROv2.new

      expect(mipro.config.num_trials).to eq(12) # default value
      expect(mipro.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Adaptive)
      expect(mipro.proposer).to be_a(DSPy::Propose::GroundedProposer)
    end

    it 'creates MIPROv2 with custom metric' do      
      custom_metric = proc { |example, prediction| true }
      mipro = DSPy::Teleprompt::MIPROv2.new(metric: custom_metric)

      expect(mipro.metric).to eq(custom_metric)
      expect(mipro.config.num_trials).to eq(12) # default value
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
      mock_proposal = DSPy::Propose::GroundedProposer::ProposalResult.new(
        candidate_instructions: [
          "Analyze the question and context step by step to provide a comprehensive answer with detailed reasoning",
          "Examine the provided context carefully and extract key information to formulate a well-reasoned response",
          "Think through the problem systematically, using the context to support your analysis and conclusion"
        ],
        analysis: {
          complexity_indicators: { requires_reasoning: true },
          common_themes: ["question_answering", "analytical_reasoning"]
        },
        metadata: { model: "test", generation_timestamp: Time.now.iso8601 },
        predictor_instructions: {
          0 => [
            "Analyze the question and context step by step to provide a comprehensive answer with detailed reasoning",
            "Examine the provided context carefully and extract key information to formulate a well-reasoned response",
            "Think through the problem systematically, using the context to support your analysis and conclusion"
          ]
        }
      )

      allow_any_instance_of(DSPy::Propose::GroundedProposer).to receive(:propose_instructions_for_program).and_return(mock_proposal)

      # Mock bootstrap to return demo candidates (new dict interface)
      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return(
        {
          0 => [
            training_examples.take(2).map { |ex| DSPy::FewShotExample.new(input: ex.input_values, output: ex.expected_values) },
            training_examples.drop(1).take(2).map { |ex| DSPy::FewShotExample.new(input: ex.input_values, output: ex.expected_values) },
            training_examples.drop(2).take(2).map { |ex| DSPy::FewShotExample.new(input: ex.input_values, output: ex.expected_values) }
          ]
        }
      )
    end

    it 'performs end-to-end MIPROv2 optimization' do
      # Use a custom metric that simulates successful evaluations
      # based on the mock program's confidence score
      custom_metric = proc do |example, prediction|
        if prediction && prediction.respond_to?(:confidence)
          prediction.confidence > 0.7  # Consider high confidence as success
        else
          false
        end
      end
      
      # Create optimizer with custom metric
      mipro = DSPy::Teleprompt::MIPROv2.new(metric: custom_metric)
      
      # Configure for faster testing using instance-level configuration
      mipro.configure do |config|
        config.num_trials = 3
        config.num_instruction_candidates = 2
        config.bootstrap_sets = 2
      end
      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result).to be_a(DSPy::Teleprompt::MIPROv2::MIPROv2Result)
      expect(result.optimized_program).not_to be_nil
      expect(result.scores).to include(:pass_rate)
      expect(result.best_score_value).to be_a(Float)
      expect(result.best_score_value).to be >= 0.0

      # MIPROv2-specific checks
      expect(result.evaluated_candidates).to be_an(Array)
      expect(result.bootstrap_statistics).to include(:num_predictors, :demo_sets_per_predictor, :avg_demos_per_set)
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
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.num_trials = 2
      end
      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result).to be_a(DSPy::Teleprompt::MIPROv2::MIPROv2Result)
    end

    it 'respects trial limit configuration' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.num_trials = 2
      end
      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result.history[:total_trials]).to be <= 2
    end

    it 'tracks optimization phases' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.num_trials = 2
      end

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

    it 'evaluates candidates concurrently when minibatching is configured' do
      custom_metric = proc do |_example, prediction|
        prediction && prediction.respond_to?(:confidence) ? prediction.confidence > 0.5 : false
      end

      mipro = DSPy::Teleprompt::MIPROv2.new(metric: custom_metric)

      mipro.configure do |config|
        config.num_trials = 1
        config.num_instruction_candidates = 1
        config.bootstrap_sets = 1
        config.minibatch_size = 2
        config.num_threads = 2
      end

      enlarged_valset = validation_examples + training_examples.take(2)

      expect(mipro).to receive(:evaluate_program).at_least(:twice).and_call_original

      mipro.compile(test_program, trainset: training_examples, valset: enlarged_valset)
    end

    it 'produces serialized optimization trace in final result' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.num_trials = 2
        config.num_instruction_candidates = 2
      end
      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

      # Verify optimization trace contains serialized candidates
      expect(result.optimization_trace).to be_a(Hash)
      
      if result.optimization_trace[:candidates]
        expect(result.optimization_trace[:candidates]).to be_an(Array)
        
        # Check that candidates are serialized as hashes, not objects
        if result.optimization_trace[:candidates].any?
          first_candidate = result.optimization_trace[:candidates].first
          expect(first_candidate).to be_a(Hash)
          expect(first_candidate).to include(:instruction, :few_shot_examples, :metadata, :config_id)
          expect(first_candidate[:instruction]).to be_a(String)
          expect(first_candidate[:few_shot_examples]).to be_a(Integer)
          expect(first_candidate[:metadata]).to be_a(Hash)
          expect(first_candidate[:config_id]).to be_a(String)
        end
      end

      # Verify the result can be serialized to JSON without object references
      json_output = nil
      expect { json_output = JSON.generate(result.to_h) }.not_to raise_error
      
      # Parse back and verify no object references remain
      parsed = JSON.parse(json_output)
      expect(json_output).not_to include("#<DSPy::Teleprompt::MIPROv2::CandidateConfig:")
      expect(json_output).not_to include("#<Object:")
      
      # Verify optimization trace structure in JSON
      if parsed["optimization_trace"] && parsed["optimization_trace"]["candidates"]
        candidates = parsed["optimization_trace"]["candidates"]
        expect(candidates).to be_an(Array)
        candidates.each do |candidate|
          expect(candidate).to be_a(Hash)
          expect(candidate.keys).to include("instruction", "few_shot_examples", "metadata", "config_id")
        end
      end
    end

    context 'with detailed hash metrics' do
      it 'stores detailed evaluation of best candidate' do
        # Create hash metric that returns detailed evaluation data
        detailed_metric = proc do |example, prediction|
          {
            passed: prediction.confidence && prediction.confidence > 0.6,
            confidence_score: prediction.confidence || 0.0,
            answer_length: prediction.answer&.length || 0,
            has_reasoning: !!(prediction.reasoning&.include?("step")),
            evaluation_timestamp: Time.now.iso8601
          }
        end

        mipro = DSPy::Teleprompt::MIPROv2.new(metric: detailed_metric)
        mipro.configure do |config|
          config.num_trials = 1
          config.num_instruction_candidates = 1
          config.bootstrap_sets = 1
        end
        result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

        # Verify detailed evaluation was captured
        expect(result.best_evaluation_result).not_to be_nil
        
        eval_result = result.best_evaluation_result
        expect(eval_result.total_examples).to eq(validation_examples.length)
        expect(eval_result.results).to be_an(Array)
        expect(eval_result.results.length).to eq(validation_examples.length)

        # Verify hash metrics are preserved
        individual_result = eval_result.results.first
        expect(individual_result.metrics).to include(:passed, :confidence_score, :answer_length, :has_reasoning, :evaluation_timestamp)
        expect(individual_result.metrics[:confidence_score]).to be_a(Numeric)
        expect(individual_result.metrics[:answer_length]).to be_a(Integer)
        expect([true, false]).to include(individual_result.metrics[:has_reasoning])
        expect(individual_result.metrics[:evaluation_timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'preserves hash metrics across serialization' do
        hash_metric = proc do |example, prediction|
          {
            passed: true,
            custom_score: 0.95,
            metadata: { test: "value" }
          }
        end

        mipro = DSPy::Teleprompt::MIPROv2.new(metric: hash_metric)
        mipro.configure do |config|
          config.num_trials = 1
          config.num_instruction_candidates = 1
          config.bootstrap_sets = 1
        end
        result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)

        # Test serialization roundtrip
        result_hash = result.to_h
        expect(result_hash[:best_evaluation_result]).not_to be_nil
        
        best_eval_hash = result_hash[:best_evaluation_result]
        expect(best_eval_hash[:results]).to be_an(Array)
        
        first_example_metrics = best_eval_hash[:results].first[:metrics]
        expect(first_example_metrics).to include(:passed, :custom_score, :metadata)
        expect(first_example_metrics[:custom_score]).to eq(0.95)
        expect(first_example_metrics[:metadata][:test]).to eq("value")
      end
    end
  end

  describe 'instruction history forwarding' do
    it 'passes stored trial history to proposer when available' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      trial_history = {
        1 => { instructions: { 0 => "Prior instruction" }, score: 0.82 }
      }
      mipro.instance_variable_set(:@trial_history, trial_history)

      proposal_result = DSPy::Propose::GroundedProposer::ProposalResult.new(
        candidate_instructions: [
          "Analyze the question carefully before answering."
        ],
        analysis: { common_themes: [] },
        metadata: { model: "test" }
      )

      proposer_double = instance_double(DSPy::Propose::GroundedProposer)
      allow(proposer_double).to receive(:propose_instructions_for_program).and_return(proposal_result)
      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return({ 0 => [] })

      expect(DSPy::Propose::GroundedProposer).to receive(:new).and_return(proposer_double)
      expect(proposer_double).to receive(:propose_instructions_for_program).with(
        trainset: training_examples,
        program: test_program,
        demo_candidates: { 0 => [] },
        trial_logs: trial_history,
        num_instruction_candidates: a_kind_of(Integer)
      ).and_return(proposal_result)

      mipro.send(:phase_2_propose_instructions, test_program, training_examples, { 0 => [] })
    end
  end

  describe 'optimization strategies' do
    let(:mock_candidates) do
      [
        create_test_evaluated_candidate(
          instruction: "Instruction 1",
          few_shot_examples: [],
          type: DSPy::Teleprompt::CandidateType::InstructionOnly,
          metadata: { rank: 0 }
        ),
        create_test_evaluated_candidate(
          instruction: "Instruction 2",
          few_shot_examples: training_examples.take(1),
          type: DSPy::Teleprompt::CandidateType::Combined,
          metadata: { rank: 1 }
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
        mipro = DSPy::Teleprompt::MIPROv2.new
        mipro.configure do |config|
          config.optimization_strategy = :greedy
        end

        selected = mipro.send(:select_candidate_greedy, mock_candidates, optimization_state)
        
        # Should select the unexplored candidate (second one)
        expect(selected).to eq(mock_candidates[1])
      end

      it 'selects highest scoring when all explored' do
        mipro = DSPy::Teleprompt::MIPROv2.new
        mipro.configure do |config|
          config.optimization_strategy = :greedy
        end

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
        mipro = DSPy::Teleprompt::MIPROv2.new
        mipro.configure do |config|
          config.optimization_strategy = :adaptive
        end

        selected = mipro.send(:select_candidate_adaptive, mock_candidates, optimization_state, 5)
        
        expect(mock_candidates).to include(selected)
        # Temperature should be updated based on progress
        expect(optimization_state[:temperature]).to be < 1.0
      end
    end

    describe 'bayesian selection' do
      it 'falls back to adaptive selection with insufficient data' do
        mipro = DSPy::Teleprompt::MIPROv2.new
        mipro.configure do |config|
          config.optimization_strategy = :bayesian
        end

        # State with only 1 scored candidate (< 3 required)
        sparse_state = {
          scores: { "config1" => 0.8 },
          exploration_counts: Hash.new(0),
          temperature: 0.5,
          best_score_history: [0.8],
          no_improvement_count: 0
        }

        selected = mipro.send(:select_candidate_bayesian, mock_candidates, sparse_state, 1)
        expect(mock_candidates).to include(selected)
      end

      it 'uses Gaussian Process for selection with sufficient data' do
        mipro = DSPy::Teleprompt::MIPROv2.new
        mipro.configure do |config|
          config.optimization_strategy = :bayesian
        end

        # Create realistic candidate configs using actual CandidateConfig class
        candidates = []
        4.times do |i|
          candidate = create_test_evaluated_candidate(
            instruction: "Instruction #{i}" * (i + 1),
            few_shot_examples: training_examples.take(2),
            metadata: { rank: i }
          )
          candidates << candidate
        end

        # State with sufficient scored candidates for GP
        rich_state = {
          scores: { 
            candidates[0].config_id => 0.6, 
            candidates[1].config_id => 0.8, 
            candidates[2].config_id => 0.7,
            candidates[3].config_id => 0.9
          },
          exploration_counts: Hash.new(0),
          temperature: 0.3,
          best_score_history: [0.6, 0.8, 0.7, 0.9],
          no_improvement_count: 0
        }

        selected = mipro.send(:select_candidate_bayesian, candidates, rich_state, 10)
        expect(candidates).to include(selected)
      end

      it 'handles GP failures gracefully' do
        mipro = DSPy::Teleprompt::MIPROv2.new
        mipro.configure do |config|
          config.optimization_strategy = :bayesian
        end

        # Mock the GP to raise an error
        allow(DSPy::Optimizers::GaussianProcess).to receive(:new).and_raise(StandardError.new("GP failed"))

        selected = mipro.send(:select_candidate_bayesian, mock_candidates, optimization_state, 5)
        expect(mock_candidates).to include(selected)
      end

      it 'encodes candidates consistently for GP features' do
        mipro = DSPy::Teleprompt::MIPROv2.new

        # Create test candidates using real CandidateConfig objects
        candidates = []
        2.times do |i|
          candidate = create_test_evaluated_candidate(
            instruction: "Test instruction #{i}",
            few_shot_examples: training_examples.take(1),
            metadata: { test_rank: i }
          )
          candidates << candidate
        end

        features = mipro.send(:encode_candidates_for_gp, candidates)

        expect(features.length).to eq(2)
        expect(features[0].length).to be > 3  # Should have multiple features
        expect(features[0]).to all(be_a(Float))  # All features should be floats
        
        # Encoding should be deterministic
        features2 = mipro.send(:encode_candidates_for_gp, candidates)
        expect(features).to eq(features2)
      end
    end
  end

  describe 'trial management data tracking' do
    it 'records trial logs and parameter score summaries during optimization' do
      mock_lm = double('MockLM', model: 'mock-lm')
      allow(DSPy).to receive(:current_lm).and_return(mock_lm)

      allow_any_instance_of(DSPy::Propose::GroundedProposer).to receive(:propose_instructions).and_return(
        DSPy::Propose::GroundedProposer::ProposalResult.new(
          candidate_instructions: [
            "Analyze the question and context step by step to provide a comprehensive answer with detailed reasoning",
            "Examine the provided context carefully and extract key information to formulate a well-reasoned response"
          ],
          analysis: {
            complexity_indicators: { requires_reasoning: true },
            common_themes: ["question_answering", "analytical_reasoning"]
          },
          metadata: { model: "test", generation_timestamp: Time.now.iso8601 }
        )
      )

      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return(
        {
          0 => [
            training_examples.take(2).map { |ex| DSPy::FewShotExample.new(input: ex.input_values, output: ex.expected_values) },
            training_examples.drop(1).take(2).map { |ex| DSPy::FewShotExample.new(input: ex.input_values, output: ex.expected_values) }
          ]
        }
      )

      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.num_trials = 2
        config.num_instruction_candidates = 2
        config.bootstrap_sets = 1
        config.optimization_strategy = :greedy
      end

      result = mipro.compile(test_program, trainset: training_examples, valset: validation_examples)
      trace = result.optimization_trace

      expect(trace[:trial_logs]).to be_a(Hash)
      expect(trace[:trial_logs]).not_to be_empty

      first_log_entry = trace[:trial_logs].values.first
      expect(first_log_entry).to include(:candidate_id, :candidate_type, :evaluation_type, :score)
      expect(first_log_entry[:evaluation_type]).to eq(:full)
      expect(first_log_entry[:score]).to be_a(Float)
      expect(first_log_entry[:instructions]).to be_a(Hash)
      expect(first_log_entry[:instructions].keys).to include(0)

      expect(trace[:param_score_dict]).to be_a(Hash)
      expect(trace[:param_score_dict]).not_to be_empty

      first_param_scores = trace[:param_score_dict].values.first
      expect(first_param_scores).to be_an(Array)
      expect(first_param_scores.first).to include(:score, :evaluation_type, :instructions)

      expect(trace[:fully_evaled_param_combos]).to be_a(Hash)
    end
  end

  describe 'early stopping' do
    it 'stops when no improvement for patience trials' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.early_stopping_patience = 2
      end

      state_no_improvement = {
        no_improvement_count: 2,
        best_score_history: [0.7, 0.7, 0.7]
      }

      should_stop = mipro.send(:should_early_stop?, state_no_improvement, 5)
      expect(should_stop).to be(true)
    end

    it 'continues when improvement is happening' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.early_stopping_patience = 2
      end

      state_with_improvement = {
        no_improvement_count: 0,
        best_score_history: [0.6, 0.7, 0.8]
      }

      should_stop = mipro.send(:should_early_stop?, state_with_improvement, 5)
      expect(should_stop).to be(false)
    end

    it 'does not stop too early' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.early_stopping_patience = 3
      end

      state_early_trial = { no_improvement_count: 5 }

      should_stop = mipro.send(:should_early_stop?, state_early_trial, 1) # Trial 1
      expect(should_stop).to be(false)
    end
  end

  describe '#serialize_optimization_trace' do
    let(:mipro) { DSPy::Teleprompt::MIPROv2.new }
    
    let(:mock_candidates) do
      [
        create_test_evaluated_candidate(
          instruction: "Analyze step by step with detailed reasoning",
          few_shot_examples: training_examples.take(2),
          type: DSPy::Teleprompt::CandidateType::Combined,
          metadata: { instruction_rank: 2 }
        ),
        create_test_evaluated_candidate(
          instruction: "Provide concise answer based on context",
          few_shot_examples: [],
          type: DSPy::Teleprompt::CandidateType::InstructionOnly,
          metadata: { instruction_rank: 1 }
        )
      ]
    end

    it 'returns empty hash when optimization_state is nil' do
      result = mipro.send(:serialize_optimization_trace, nil)
      expect(result).to eq({})
    end

    it 'returns empty hash when optimization_state is empty' do
      result = mipro.send(:serialize_optimization_trace, {})
      expect(result).to eq({})
    end

    it 'preserves optimization state without candidates' do
      optimization_state = {
        temperature: 0.8,
        best_score_history: [0.6, 0.7, 0.8],
        exploration_counts: { "abc123" => 2, "def456" => 1 },
        diversity_scores: { "abc123" => 0.4, "def456" => 0.7 }
      }

      result = mipro.send(:serialize_optimization_trace, optimization_state)
      
      expect(result).to eq(optimization_state)
      expect(result[:temperature]).to eq(0.8)
      expect(result[:best_score_history]).to eq([0.6, 0.7, 0.8])
      expect(result[:exploration_counts]).to eq({ "abc123" => 2, "def456" => 1 })
      expect(result[:diversity_scores]).to eq({ "abc123" => 0.4, "def456" => 0.7 })
    end

    it 'serializes candidates array to hash format' do
      optimization_state = {
        candidates: mock_candidates,
        temperature: 0.5,
        scores: { mock_candidates.first.config_id => 0.85 }
      }

      result = mipro.send(:serialize_optimization_trace, optimization_state)
      
      expect(result[:candidates]).to be_an(Array)
      expect(result[:candidates].size).to eq(2)
      
      # Check first candidate serialization
      first_candidate = result[:candidates][0]
      expect(first_candidate).to be_a(Hash)
      expect(first_candidate[:instruction]).to eq("Analyze step by step with detailed reasoning")
      expect(first_candidate[:few_shot_examples]).to eq(2) # Count, not actual examples
      expect(first_candidate[:metadata]).to eq({ instruction_rank: 2 })
      expect(first_candidate[:config_id]).to be_a(String)
      expect(first_candidate[:config_id].length).to be > 6  # Should be a reasonable length
      
      # Check second candidate serialization
      second_candidate = result[:candidates][1]
      expect(second_candidate).to be_a(Hash)
      expect(second_candidate[:instruction]).to eq("Provide concise answer based on context")
      expect(second_candidate[:few_shot_examples]).to eq(0) # No examples
      expect(second_candidate[:metadata]).to eq({ instruction_rank: 1 })
      expect(second_candidate[:config_id]).to be_a(String)
      
      # Verify other state is preserved
      expect(result[:temperature]).to eq(0.5)
      expect(result[:scores]).to eq({ mock_candidates.first.config_id => 0.85 })
    end

    it 'does not modify the original optimization_state' do
      original_state = {
        candidates: mock_candidates,
        temperature: 0.7,
        immutable_data: { nested: "value" }
      }
      
      original_candidates = original_state[:candidates]
      original_temperature = original_state[:temperature]
      
      result = mipro.send(:serialize_optimization_trace, original_state)
      
      # Original state should be unchanged
      expect(original_state[:candidates]).to equal(original_candidates) # Same object reference
      expect(original_state[:temperature]).to eq(original_temperature)
      expect(original_state[:immutable_data][:nested]).to eq("value")
      
      # Result should be different
      expect(result[:candidates]).not_to equal(original_candidates)
      expect(result[:candidates]).to be_an(Array)
      expect(result[:candidates].first).to be_a(Hash)
    end

    it 'handles empty candidates array' do
      optimization_state = {
        candidates: [],
        temperature: 0.9,
        other_data: "preserved"
      }

      result = mipro.send(:serialize_optimization_trace, optimization_state)
      
      expect(result[:candidates]).to eq([])
      expect(result[:temperature]).to eq(0.9)
      expect(result[:other_data]).to eq("preserved")
    end

    it 'creates serializable JSON output for complex optimization trace' do
      complex_state = {
        candidates: mock_candidates,
        temperature: 0.6,
        best_score_history: [0.5, 0.7, 0.8, 0.82],
        exploration_counts: { 
          mock_candidates[0].config_id => 3, 
          mock_candidates[1].config_id => 2 
        },
        diversity_scores: { 
          mock_candidates[0].config_id => 0.45, 
          mock_candidates[1].config_id => 0.72 
        },
        no_improvement_count: 1,
        phase_timestamps: {
          bootstrap_start: "2024-01-01T10:00:00Z",
          optimization_start: "2024-01-01T10:05:00Z"
        }
      }

      result = mipro.send(:serialize_optimization_trace, complex_state)
      
      # Test that the result can be converted to JSON without errors
      json_output = nil
      expect { json_output = JSON.generate(result) }.not_to raise_error
      
      # Verify JSON can be parsed back
      parsed = JSON.parse(json_output, symbolize_names: true)
      expect(parsed[:candidates]).to be_an(Array)
      expect(parsed[:candidates].size).to eq(2)
      expect(parsed[:candidates][0][:instruction]).to eq("Analyze step by step with detailed reasoning")
      expect(parsed[:temperature]).to eq(0.6)
      expect(parsed[:best_score_history]).to eq([0.5, 0.7, 0.8, 0.82])
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
      
      candidate = create_test_evaluated_candidate(
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
      light_mipro = DSPy::Teleprompt::MIPROv2.new
      light_mipro.configure do |config|
        config.num_trials = 5
      end
      
      medium_mipro = DSPy::Teleprompt::MIPROv2.new
      medium_mipro.configure do |config|
        config.num_trials = 10
      end
      
      heavy_mipro = DSPy::Teleprompt::MIPROv2.new
      heavy_mipro.configure do |config|
        config.num_trials = 20
      end

      expect(light_mipro.send(:infer_auto_mode)).to eq("light")
      expect(medium_mipro.send(:infer_auto_mode)).to eq("medium")
      expect(heavy_mipro.send(:infer_auto_mode)).to eq("heavy")
    end
  end

  describe 'compilation with mocked components' do
    it 'works with mocked components' do
      mipro = DSPy::Teleprompt::MIPROv2.new
      mipro.configure do |config|
        config.num_trials = 1
      end

      # Mock components to avoid complex setup
      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return(
        {
          0 => [
            training_examples.take(1).map { |ex| DSPy::FewShotExample.new(input: ex.input_values, output: ex.expected_values) }
          ]
        }
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

  describe 'dry-configurable pattern (TDD failing tests)' do
    describe 'class-level configuration' do
      it 'supports configure block for default settings' do
        # This test will fail until we implement dry-configurable
        expect {
          DSPy::Teleprompt::MIPROv2.configure do |config|
            config.optimization_strategy = :bayesian
            config.num_trials = 30
            config.bootstrap_sets = 10
          end
        }.not_to raise_error

        # Test that configuration is applied to new instances
        optimizer = DSPy::Teleprompt::MIPROv2.new
        expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
        expect(optimizer.config.num_trials).to eq(30)
        expect(optimizer.config.bootstrap_sets).to eq(10)
      end

      it 'supports symbol-based optimization strategies' do
        expect {
          DSPy::Teleprompt::MIPROv2.configure do |config|
            config.optimization_strategy = :greedy
          end
        }.not_to raise_error
        
        expect {
          DSPy::Teleprompt::MIPROv2.configure do |config|
            config.optimization_strategy = :adaptive
          end
        }.not_to raise_error
        
        expect {
          DSPy::Teleprompt::MIPROv2.configure do |config|
            config.optimization_strategy = :bayesian
          end
        }.not_to raise_error
      end

      it 'rejects invalid optimization strategies' do
        # Class-level configuration doesn't validate immediately,
        # validation happens when creating instance
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.optimization_strategy = :invalid_strategy
        end

        expect {
          DSPy::Teleprompt::MIPROv2.new
        }.to raise_error(ArgumentError, /Invalid optimization strategy/)
      end
    end

    describe 'instance-level configuration' do
      it 'supports configure block on instances' do
        # Reset class config first to ensure clean state
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.optimization_strategy = :adaptive  # Set valid default
        end
        
        optimizer = DSPy::Teleprompt::MIPROv2.new
        
        expect {
          optimizer.configure do |config|
            config.optimization_strategy = :adaptive
            config.num_trials = 15
            config.bootstrap_sets = 5
          end
        }.not_to raise_error

        expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Adaptive)
        expect(optimizer.config.num_trials).to eq(15)
        expect(optimizer.config.bootstrap_sets).to eq(5)
      end

      it 'rejects invalid optimization strategies on instances' do
        # Reset class config first to ensure clean state
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.optimization_strategy = :adaptive  # Set valid default
        end
        
        optimizer = DSPy::Teleprompt::MIPROv2.new
        
        expect {
          optimizer.configure do |config|
            config.optimization_strategy = :invalid_strategy
          end
        }.to raise_error(ArgumentError, /Invalid optimization strategy/)
      end

      it 'overrides class-level configuration' do
        # Set class defaults
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.num_trials = 30
          config.optimization_strategy = :bayesian
        end

        # Instance should override
        optimizer = DSPy::Teleprompt::MIPROv2.new
        optimizer.configure do |config|
          config.num_trials = 10
          config.optimization_strategy = :greedy
        end

        expect(optimizer.config.num_trials).to eq(10)
        expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Greedy)
      end
    end

    describe 'AutoMode with new configuration' do
      it 'creates pre-configured instances without old config classes' do
        light_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.light
        expect(light_optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Greedy)
        expect(light_optimizer.config.num_trials).to eq(6)

        medium_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium  
        expect(medium_optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Adaptive)
        expect(medium_optimizer.config.num_trials).to eq(12)

        heavy_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.heavy
        expect(heavy_optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
        expect(heavy_optimizer.config.num_trials).to eq(18)
      end
    end

    describe 'new constructor without config parameter' do
      it 'creates optimizer without config parameter' do
        simple_metric = proc { |example, prediction| true }
        expect {
          DSPy::Teleprompt::MIPROv2.new(metric: simple_metric)
        }.not_to raise_error
      end

      it 'rejects old config parameter pattern' do
        # This should fail since we're removing backwards compatibility
        simple_metric = proc { |example, prediction| true }
        expect {
          DSPy::Teleprompt::MIPROv2.new(metric: simple_metric, config: "any_value")
        }.to raise_error(ArgumentError, /config parameter is no longer supported/)
      end
    end

    describe 'T::Enum integration' do
      it 'converts optimization_strategy to T::Enum internally' do
        optimizer = DSPy::Teleprompt::MIPROv2.new
        optimizer.configure do |config|
          config.optimization_strategy = :bayesian
        end

        # Internal usage should work with T::Enum comparison
        expect(optimizer.config.optimization_strategy).to be_a(DSPy::Teleprompt::OptimizationStrategy)
        expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
      end
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
