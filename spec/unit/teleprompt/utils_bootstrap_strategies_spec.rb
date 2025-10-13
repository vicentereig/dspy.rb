# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets (Python-compatible)' do
  # Create a simple test signature - use let! to define per-test instances
  let(:signature_class) do
    Class.new(DSPy::Signature) do
      description "Answer questions"

      input do
        const :question, String, description: "A question"
      end

      output do
        const :answer, String, description: "The answer"
      end
    end
  end

  # Create a simple test module (predictor)
  let(:module_class) do
    sig_class = signature_class  # Capture in closure
    Class.new(DSPy::Module) do
      define_method(:initialize) do
        super()
        @predictor = DSPy::Predict.new(sig_class)
        @signature_class = sig_class
      end

      define_method(:call) do |question:|
        @predictor.call(question: question)
      end

      define_method(:signature_class) do
        @signature_class
      end
    end
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: signature_class,
        input: { question: "What is 2+2?" },
        expected: { answer: "4" },
        id: "ex1"
      ),
      DSPy::Example.new(
        signature_class: signature_class,
        input: { question: "What is 3+3?" },
        expected: { answer: "6" },
        id: "ex2"
      ),
      DSPy::Example.new(
        signature_class: signature_class,
        input: { question: "What is 5+5?" },
        expected: { answer: "10" },
        id: "ex3"
      )
    ]
  end

  let(:student) do
    module_class.new.tap do |mod|
      # Mock the predictor to return expected answers
      allow(mod).to receive(:call) do |question:|
        case question
        when "What is 2+2?"
          OpenStruct.new(answer: "4", to_h: { answer: "4" })
        when "What is 3+3?"
          OpenStruct.new(answer: "6", to_h: { answer: "6" })
        when "What is 5+5?"
          OpenStruct.new(answer: "10", to_h: { answer: "10" })
        else
          OpenStruct.new(answer: "unknown", to_h: { answer: "unknown" })
        end
      end
    end
  end

  describe 'return value structure' do
    it 'returns hash mapping predictor indices to arrays of demo set arrays' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        5,  # num_candidate_sets
        trainset
      )

      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_an(Integer))

      # Each predictor index should have an array of demo sets
      result.each do |predictor_idx, demo_sets|
        expect(demo_sets).to be_an(Array)
        # Each demo set is an array of FewShotExample objects
        demo_sets.each do |demo_set|
          expect(demo_set).to be_an(Array)
          demo_set.each do |demo|
            expect(demo).to be_a(DSPy::FewShotExample)
          end
        end
      end
    end
  end

  describe 'ZeroShot strategy (seed = -3)' do
    it 'creates empty demo sets for zero-shot strategy' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,  # num_candidate_sets (accounts for -3, -2, -1)
        trainset,
        include_non_bootstrapped: true
      )

      # First demo set should be empty (ZeroShot)
      expect(result[0].first).to eq([])
    end

    it 'skips ZeroShot when include_non_bootstrapped is false' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        include_non_bootstrapped: false
      )

      # Should not include empty demo set
      result.each do |_predictor_idx, demo_sets|
        demo_sets.each do |demo_set|
          expect(demo_set).not_to eq([])
        end
      end
    end
  end

  describe 'LabeledOnly strategy (seed = -2)' do
    it 'uses trainset directly as labeled demos' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,  # num_candidate_sets
        trainset,
        max_labeled_demos: 2,
        include_non_bootstrapped: true
      )

      # Second demo set should contain labeled examples (index 1, after ZeroShot at index 0)
      labeled_set = result[0][1]

      expect(labeled_set.size).to be <= 2

      # Check that demos come from trainset
      labeled_set.each do |demo|
        expect(demo).to be_a(DSPy::FewShotExample)
        expect(demo.input).to be_a(Hash)
        expect(demo.output).to be_a(Hash)
      end
    end

    it 'samples labeled examples when labeled_sample=true' do
      # Test reproducibility with seed
      result1 = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_labeled_demos: 2,
        labeled_sample: true,
        seed: 42
      )

      result2 = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_labeled_demos: 2,
        labeled_sample: true,
        seed: 42
      )

      # Same seed should produce same sampling
      expect(result1[0][1]).to eq(result2[0][1])
    end

    it 'takes first k examples when labeled_sample=false' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_labeled_demos: 2,
        labeled_sample: false
      )

      labeled_set = result[0][1]

      # Should take first 2 examples from trainset
      expect(labeled_set.size).to eq(2)
      expect(labeled_set[0].input[:question]).to eq("What is 2+2?")
      expect(labeled_set[1].input[:question]).to eq("What is 3+3?")
    end

    it 'skips LabeledOnly when max_labeled_demos is 0' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_labeled_demos: 0,
        include_non_bootstrapped: true
      )

      # Count non-empty demo sets
      # Should have: ZeroShot (empty), Unshuffled, Shuffled
      # Should NOT have LabeledOnly
      demo_sets = result[0]
      non_empty_sets = demo_sets.reject(&:empty?)

      # Expect only Unshuffled and Shuffled (2 non-empty sets)
      expect(non_empty_sets.size).to eq(2)
    end

    it 'skips LabeledOnly when include_non_bootstrapped is false' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_labeled_demos: 2,
        include_non_bootstrapped: false
      )

      # Should only have bootstrapped demos (Unshuffled and Shuffled)
      # No ZeroShot, No LabeledOnly
      demo_sets = result[0]

      expect(demo_sets.size).to eq(2)  # Unshuffled + Shuffled
    end
  end

  describe 'Unshuffled strategy (seed = -1)' do
    it 'creates bootstrapped demos without shuffling trainset' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_bootstrapped_demos: 2,
        max_labeled_demos: 0
      )

      # Find the unshuffled demo set (index 2 if include_non_bootstrapped=true with ZeroShot and LabeledOnly)
      # Actually with max_labeled_demos=0, LabeledOnly is skipped
      # So: index 0 = ZeroShot, index 1 = Unshuffled
      unshuffled_set = result[0][1]

      expect(unshuffled_set).not_to be_empty
      expect(unshuffled_set.size).to be <= 2

      # Verify demos are FewShotExamples
      unshuffled_set.each do |demo|
        expect(demo).to be_a(DSPy::FewShotExample)
      end
    end

    it 'always includes Unshuffled even when include_non_bootstrapped=false' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_bootstrapped_demos: 2,
        include_non_bootstrapped: false
      )

      # Should have at least one bootstrapped demo set
      expect(result[0]).not_to be_empty
    end
  end

  describe 'Shuffled strategies (seed >= 0)' do
    it 'creates shuffled bootstrapped demos with random sizes' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        5,  # Creates seeds: -3, -2, -1, 0, 1
        trainset,
        max_bootstrapped_demos: 3,
        min_num_samples: 1,
        max_labeled_demos: 0,
        include_non_bootstrapped: false  # Skip ZeroShot and LabeledOnly for clarity
      )

      # Should have: Unshuffled (seed=-1), Shuffled (seed=0), Shuffled (seed=1)
      expect(result[0].size).to eq(3)

      # All should be non-empty
      result[0].each do |demo_set|
        expect(demo_set).not_to be_empty
      end
    end

    it 'produces reproducible results with same seed' do
      result1 = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        5,
        trainset,
        max_bootstrapped_demos: 2,
        seed: 42,
        include_non_bootstrapped: false
      )

      result2 = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        5,
        trainset,
        max_bootstrapped_demos: 2,
        seed: 42,
        include_non_bootstrapped: false
      )

      # Same seed should produce identical results
      expect(result1).to eq(result2)
    end

    it 'produces different results with different num_candidate_sets' do
      # Different num_candidate_sets creates different shuffled strategies
      result1 = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        5,  # Creates: Unshuffled, Shuffled(0), Shuffled(1)
        trainset,
        max_bootstrapped_demos: 2,
        max_labeled_demos: 0,
        include_non_bootstrapped: false
      )

      result2 = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        6,  # Creates: Unshuffled, Shuffled(0), Shuffled(1), Shuffled(2)
        trainset,
        max_bootstrapped_demos: 2,
        max_labeled_demos: 0,
        include_non_bootstrapped: false
      )

      # Different number of candidate sets should produce different results
      expect(result1[0].size).to eq(3)
      expect(result2[0].size).to eq(4)
      expect(result1).not_to eq(result2)
    end
  end

  describe 'num_candidate_sets loop mechanics' do
    it 'creates correct number of demo sets accounting for special seeds' do
      num_candidate_sets = 6

      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        num_candidate_sets,
        trainset,
        max_labeled_demos: 1,
        include_non_bootstrapped: true
      )

      # Should create num_candidate_sets demo sets total:
      # -3 (ZeroShot), -2 (LabeledOnly), -1 (Unshuffled), 0 (Shuffled), 1 (Shuffled), 2 (Shuffled)
      expect(result[0].size).to eq(num_candidate_sets)
    end

    it 'handles small num_candidate_sets correctly' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        3,  # Only creates: -3, -2, -1 (no shuffled)
        trainset,
        include_non_bootstrapped: true
      )

      # Should create 3 demo sets
      expect(result[0].size).to eq(3)
    end
  end

  describe 'multiple predictors' do
    it 'creates demo sets for each predictor in module' do
      # For now, we assume single predictor modules
      # This test documents the expected behavior for future multi-predictor support
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset
      )

      # Currently should have one predictor (index 0)
      expect(result.keys).to eq([0])

      # Each predictor should have multiple demo sets
      expect(result[0]).to be_an(Array)
      expect(result[0].size).to be > 0
    end
  end

  describe 'metric validation' do
    it 'uses custom metric when provided' do
      # Custom metric that only accepts even numbers
      metric = lambda do |example, prediction|
        prediction[:answer].to_i.even?
      end

      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_bootstrapped_demos: 3,
        max_labeled_demos: 0,
        metric: metric,
        include_non_bootstrapped: false
      )

      # Bootstrapped demos should only include examples that passed the metric
      result[0].each do |demo_set|
        demo_set.each do |demo|
          answer = demo.output[:answer]
          expect(answer.to_i.even?).to be true
        end
      end
    end

    it 'uses default matching when no metric provided' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        4,
        trainset,
        max_bootstrapped_demos: 2,
        max_labeled_demos: 0,
        include_non_bootstrapped: false
      )

      # All examples should match since student is mocked to return expected answers
      expect(result[0]).not_to be_empty
    end
  end
end
