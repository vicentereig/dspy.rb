require 'spec_helper'
require 'ostruct'
require 'dspy/teleprompt/utils'
require 'dspy/signature'
require 'dspy/predict'
require 'dspy/example'

# Test signature for bootstrap utilities testing
class BootstrapMath < DSPy::Signature
  description "Solve basic math problems with step-by-step explanations."

  input do
    const :problem, String, description: "A simple math problem"
  end

  output do
    const :answer, Integer, description: "The numerical answer"
    const :explanation, String, description: "Step-by-step solution"
  end
end

# Mock predictor for testing bootstrap
class MockMathPredictor
  def call(problem:)
    result = case problem
    when "2 + 3"
      OpenStruct.new(problem: problem, answer: 5, explanation: "Add 2 and 3 to get 5")
    when "10 - 4"
      OpenStruct.new(problem: problem, answer: 6, explanation: "Subtract 4 from 10 to get 6")
    when "3 × 7"
      OpenStruct.new(problem: problem, answer: 21, explanation: "Multiply 3 by 7 to get 21")
    when "error_case"
      raise "Simulated prediction error"
    else
      OpenStruct.new(problem: problem, answer: 0, explanation: "Unknown problem")
    end
    
    # Add to_h method to the result
    result.define_singleton_method(:to_h) do
      { answer: self.answer, explanation: self.explanation }
    end
    
    result
  end
end

RSpec.describe DSPy::Teleprompt::Utils do
  let(:mock_predictor) { MockMathPredictor.new }

  describe DSPy::Teleprompt::Utils::BootstrapConfig do
    it 'has sensible defaults' do
      config = DSPy::Teleprompt::Utils::BootstrapConfig.new

      expect(config.max_bootstrapped_examples).to eq(4)
      expect(config.max_labeled_examples).to eq(16)
      expect(config.num_candidate_sets).to eq(10)
      expect(config.max_errors).to eq(5)
      expect(config.num_threads).to eq(1)
      expect(config.success_threshold).to eq(0.8)
      expect(config.minibatch_size).to eq(50)
    end

    it 'allows configuration customization' do
      config = DSPy::Teleprompt::Utils::BootstrapConfig.new
      config.max_bootstrapped_examples = 8
      config.num_candidate_sets = 5
      config.minibatch_size = 25

      expect(config.max_bootstrapped_examples).to eq(8)
      expect(config.num_candidate_sets).to eq(5)
      expect(config.minibatch_size).to eq(25)
    end
  end

  describe DSPy::Teleprompt::Utils::BootstrapResult do
    let(:candidate_sets) do
      [
        [create_test_example("2 + 2", 4)],
        [create_test_example("3 + 3", 6)]
      ]
    end

    let(:successful_examples) { [create_test_example("5 + 5", 10)] }
    let(:failed_examples) { [create_test_example("error", 0)] }
    let(:statistics) { { total: 4, successful: 3, failed: 1 } }

    let(:result) do
      DSPy::Teleprompt::Utils::BootstrapResult.new(
        candidate_sets: candidate_sets,
        successful_examples: successful_examples,
        failed_examples: failed_examples,
        statistics: statistics
      )
    end

    it 'stores bootstrap results correctly' do
      expect(result.candidate_sets).to eq(candidate_sets)
      expect(result.successful_examples).to eq(successful_examples)
      expect(result.failed_examples).to eq(failed_examples)
      expect(result.statistics).to eq(statistics)
    end

    it 'calculates success rate' do
      expect(result.success_rate).to eq(0.5) # 1 successful / 2 total
    end

    it 'calculates total examples' do
      expect(result.total_examples).to eq(2)
    end

    it 'handles empty results' do
      empty_result = DSPy::Teleprompt::Utils::BootstrapResult.new(
        candidate_sets: [],
        successful_examples: [],
        failed_examples: [],
        statistics: {}
      )

      expect(empty_result.success_rate).to eq(0.0)
      expect(empty_result.total_examples).to eq(0)
    end

    it 'freezes data structures' do
      expect(result.candidate_sets).to be_frozen
      expect(result.successful_examples).to be_frozen
      expect(result.failed_examples).to be_frozen
      expect(result.statistics).to be_frozen
    end
  end

  describe '.create_n_fewshot_demo_sets' do
    let(:training_examples) do
      [
        create_test_example("2 + 3", 5),
        create_test_example("10 - 4", 6),
        create_test_example("3 × 7", 21),
        create_test_example("error_case", 0),
        create_test_example("unknown", 42)
      ]
    end

    let(:config) do
      config = DSPy::Teleprompt::Utils::BootstrapConfig.new
      config.max_bootstrapped_examples = 2
      config.max_labeled_examples = 10
      config.num_candidate_sets = 3
      config.max_errors = 2
      config
    end

    it 'creates bootstrap result with candidate sets' do
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        mock_predictor,
        training_examples,
        config: config
      )

      expect(result).to be_a(DSPy::Teleprompt::Utils::BootstrapResult)
      expect(result.candidate_sets.size).to eq(3)
      expect(result.successful_examples.size).to be > 0
      expect(result.statistics).to include(:total_trainset, :successful_count, :success_rate)
    end

    it 'handles successful predictions correctly' do
      successful_examples = [
        create_test_example("2 + 3", 5),
        create_test_example("10 - 4", 6)
      ]

      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        mock_predictor,
        successful_examples,
        config: config
      )

      expect(result.successful_examples.size).to be >= 2
      expect(result.statistics[:success_rate]).to be > 0.5
    end

    it 'filters input fields from bootstrap examples to prevent validation errors' do
      # This test verifies the fix for the MIPROv2 hanging issue
      # The mock predictor returns predictions that include both input and output fields
      # The bootstrap process should filter out input fields to prevent DSPy::Example validation errors
      
      examples_with_matching_outputs = [
        create_test_example("2 + 3", 5), # This will match prediction: {answer: 5, explanation: "Add 2 and 3 to get 5"}
        create_test_example("10 - 4", 6) # This will match prediction: {answer: 6, explanation: "Subtract 4 from 10 to get 6"}
      ]

      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        mock_predictor,
        examples_with_matching_outputs,
        config: config
      )

      # Verify that bootstrap examples were created successfully
      expect(result.successful_examples.size).to be >= 2
      
      # Verify that successful bootstrap examples only contain output fields
      bootstrap_example = result.successful_examples.first
      expect(bootstrap_example.expected_values).to include(:answer, :explanation)
      expect(bootstrap_example.expected_values).not_to include(:problem) # input field should be filtered out
      
      # Verify input fields are preserved in input_values 
      expect(bootstrap_example.input_values).to include(:problem)
      expect(bootstrap_example.input_values).not_to include(:answer, :explanation)
    end

    it 'handles bootstrap process when predictions include extra input fields' do
      # Create a mock predictor that includes input fields in its output
      # This simulates the exact scenario that caused the hanging bug
      problematic_predictor = Class.new do
        def call(problem:)
          result = case problem
          when "2 + 3"
            OpenStruct.new(
              problem: problem,     # INPUT field contaminating the prediction
              answer: 5,           # OUTPUT field  
              explanation: "Add 2 and 3 to get 5" # OUTPUT field
            )
          when "10 - 4"  
            OpenStruct.new(
              problem: problem,     # INPUT field contaminating the prediction
              answer: 6,           # OUTPUT field
              explanation: "Subtract 4 from 10 to get 6" # OUTPUT field
            )
          else
            OpenStruct.new(
              problem: problem,
              answer: 0, 
              explanation: "Unknown problem"
            )
          end
          
          # Add to_h method that includes ALL fields (input + output)
          result.define_singleton_method(:to_h) do
            { problem: self.problem, answer: self.answer, explanation: self.explanation }
          end
          
          result
        end
      end.new

      examples = [
        create_test_example("2 + 3", 5),
        create_test_example("10 - 4", 6)
      ]

      # This should NOT hang and should complete successfully
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        problematic_predictor,
        examples,
        config: config
      )

      # Verify successful completion without hanging
      expect(result).to be_a(DSPy::Teleprompt::Utils::BootstrapResult)
      expect(result.successful_examples.size).to eq(2)
      expect(result.statistics[:success_rate]).to eq(1.0)
      
      # Verify that each bootstrap example only contains output fields in expected_values
      result.successful_examples.each do |bootstrap_example|
        expect(bootstrap_example.expected_values.keys).to contain_exactly(:answer, :explanation)
        expect(bootstrap_example.input_values.keys).to contain_exactly(:problem)
      end
    end

    it 'prevents infinite loops when prediction validation consistently fails' do
      # Create a predictor that always produces predictions that would fail validation
      # without field filtering (because it includes input fields)
      always_contaminated_predictor = Class.new do
        def call(problem:)
          # Always return prediction with contaminating input field
          # But make sure the output matches expected values for successful bootstrap
          result = OpenStruct.new(
            problem: "contaminated_#{problem}", # This would cause DSPy::Example validation to fail
            answer: 1, # This matches the expected value from create_test_example("test", 1)
            explanation: "Unknown problem" # This matches MockMathPredictor behavior for "test"
          )
          
          result.define_singleton_method(:to_h) do
            { problem: self.problem, answer: self.answer, explanation: self.explanation }
          end
          
          result
        end
      end.new

      # Use expected values that match the predictor output
      examples = [create_test_example("test", 1)] # This will match predictor's answer: 1
      
      config_with_low_limits = DSPy::Teleprompt::Utils::BootstrapConfig.new
      config_with_low_limits.max_labeled_examples = 1
      config_with_low_limits.max_errors = 2

      # This should complete without hanging, even though predictions are "contaminated"
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        always_contaminated_predictor,
        examples,
        config: config_with_low_limits
      )

      # Should successfully create bootstrap examples because field filtering removes contamination
      expect(result.successful_examples.size).to eq(1)
      expect(result.successful_examples.first.expected_values).not_to include(:problem)
      expect(result.successful_examples.first.expected_values).to include(:answer, :explanation)
    end

    it 'handles prediction errors gracefully' do
      error_examples = [
        create_test_example("error_case", 0),
        create_test_example("2 + 3", 5)
      ]

      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        mock_predictor,
        error_examples,
        config: config
      )

      expect(result.failed_examples.size).to be > 0
      expect(result.statistics).to include(:failed_count)
    end

    it 'respects max_labeled_examples limit' do
      config.max_labeled_examples = 2
      
      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        mock_predictor,
        training_examples,
        config: config
      )

      expect(result.successful_examples.size).to be <= 2
    end

    it 'uses custom metric when provided' do
      custom_metric = proc { |example, prediction| prediction[:answer] > 0 }

      result = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        mock_predictor,
        training_examples,
        config: config,
        metric: custom_metric
      )

      expect(result).to be_a(DSPy::Teleprompt::Utils::BootstrapResult)
    end
  end

  describe '.eval_candidate_program' do
    let(:test_examples) do
      [
        create_test_example("2 + 3", 5),
        create_test_example("10 - 4", 6)
      ]
    end

    let(:config) { DSPy::Teleprompt::Utils::BootstrapConfig.new }

    it 'evaluates program on small datasets' do
      config.minibatch_size = 50

      result = DSPy::Teleprompt::Utils.eval_candidate_program(
        mock_predictor,
        test_examples,
        config: config
      )

      expect(result).to be_a(DSPy::Evaluate::BatchEvaluationResult)
      expect(result.total_examples).to eq(2)
    end

    it 'uses minibatch evaluation for large datasets' do
      config.minibatch_size = 1

      result = DSPy::Teleprompt::Utils.eval_candidate_program(
        mock_predictor,
        test_examples,
        config: config
      )

      expect(result).to be_a(DSPy::Evaluate::BatchEvaluationResult)
      expect(result.total_examples).to eq(1) # Should sample only 1 due to minibatch_size
    end

    it 'handles custom metrics' do
      custom_metric = proc { |example, prediction| prediction[:answer] == example.expected_values[:answer] }

      result = DSPy::Teleprompt::Utils.eval_candidate_program(
        mock_predictor,
        test_examples,
        config: config,
        metric: custom_metric
      )

      expect(result).to be_a(DSPy::Evaluate::BatchEvaluationResult)
    end
  end

  describe 'private methods' do
    describe '.ensure_typed_examples' do
      it 'returns DSPy::Example objects unchanged' do
        examples = [create_test_example("test", 42)]
        
        result = DSPy::Teleprompt::Utils.send(:ensure_typed_examples, examples)
        
        expect(result).to eq(examples)
        expect(result.first).to be_a(DSPy::Example)
      end

      it 'raises error for non-DSPy::Example objects' do
        non_example_objects = [
          {
            input: { problem: "test problem" },
            expected: { answer: 42, explanation: "test explanation" },
            signature_class: BootstrapMath
          }
        ]

        expect {
          DSPy::Teleprompt::Utils.send(:ensure_typed_examples, non_example_objects)
        }.to raise_error(ArgumentError, /All examples must be DSPy::Example instances/)
      end

      it 'raises error for invalid objects' do
        invalid_examples = [{ problem: "test", answer: "test" }]
        
        expect {
          DSPy::Teleprompt::Utils.send(:ensure_typed_examples, invalid_examples)
        }.to raise_error(ArgumentError, /All examples must be DSPy::Example instances/)
      end
    end

    describe '.create_successful_bootstrap_example' do
      it 'creates bootstrap example with metadata' do
        original = create_test_example("2 + 2", 4)
        prediction_hash = { answer: 4, explanation: "Two plus two equals four" }

        result = DSPy::Teleprompt::Utils.send(
          :create_successful_bootstrap_example,
          original,
          prediction_hash
        )

        expect(result).to be_a(DSPy::Example)
        expect(result.input_values).to eq(original.input_values)
        expect(result.expected_values[:answer]).to eq(4)
        expect(result.metadata[:source]).to eq("bootstrap")
        expect(result.metadata).to include(:original_expected, :bootstrap_timestamp)
      end

      it 'accepts pre-filtered prediction hash directly' do
        original = create_test_example("5 + 7", 12)
        filtered_prediction = { answer: 12, explanation: "Add five and seven" }

        result = DSPy::Teleprompt::Utils.send(
          :create_successful_bootstrap_example,
          original,
          filtered_prediction
        )

        expect(result.expected_values).to eq(filtered_prediction)
        expect(result.input_values).to eq(original.input_values)
        expect(result.metadata[:source]).to eq("bootstrap")
      end
    end

    describe '.extract_output_fields_from_prediction' do
      let(:prediction) do
        OpenStruct.new(
          problem: "2 + 3", # input field - should be filtered out
          answer: 5,        # output field - should be kept
          explanation: "Add 2 and 3 to get 5" # output field - should be kept
        ).tap do |pred|
          pred.define_singleton_method(:to_h) do
            { problem: problem, answer: answer, explanation: explanation }
          end
        end
      end

      it 'extracts only output fields from prediction' do
        result = DSPy::Teleprompt::Utils.send(
          :extract_output_fields_from_prediction,
          prediction,
          BootstrapMath
        )

        expect(result).to eq({
          answer: 5,
          explanation: "Add 2 and 3 to get 5"
        })
        expect(result).not_to include(:problem)
      end

      it 'handles missing output fields gracefully' do
        incomplete_prediction = OpenStruct.new(
          problem: "incomplete",
          answer: 42
          # missing explanation field
        ).tap do |pred|
          pred.define_singleton_method(:to_h) do
            { problem: problem, answer: answer }
          end
        end

        result = DSPy::Teleprompt::Utils.send(
          :extract_output_fields_from_prediction,
          incomplete_prediction,
          BootstrapMath
        )

        expect(result).to eq({ answer: 42 })
        expect(result).not_to include(:explanation)
        expect(result).not_to include(:problem)
      end

      it 'returns empty hash when no output fields match' do
        input_only_prediction = OpenStruct.new(
          problem: "test",
          unrelated_field: "value"
        ).tap do |pred|
          pred.define_singleton_method(:to_h) do
            { problem: problem, unrelated_field: unrelated_field }
          end
        end

        result = DSPy::Teleprompt::Utils.send(
          :extract_output_fields_from_prediction,
          input_only_prediction,
          BootstrapMath
        )

        expect(result).to eq({})
      end

      it 'works with different signature classes' do
        # Create a signature with different output fields
        sentiment_signature = Class.new(DSPy::Signature) do
          description "Analyze sentiment"
          
          input do
            const :text, String
          end

          output do
            const :sentiment, String
            const :confidence, Float
          end
        end

        sentiment_prediction = OpenStruct.new(
          text: "This is great!", # input field
          sentiment: "positive",  # output field
          confidence: 0.95,      # output field
          extra_field: "ignored" # unrecognized field
        ).tap do |pred|
          pred.define_singleton_method(:to_h) do
            { text: text, sentiment: sentiment, confidence: confidence, extra_field: extra_field }
          end
        end

        result = DSPy::Teleprompt::Utils.send(
          :extract_output_fields_from_prediction,
          sentiment_prediction,
          sentiment_signature
        )

        expect(result).to eq({
          sentiment: "positive",
          confidence: 0.95
        })
        expect(result).not_to include(:text)
        expect(result).not_to include(:extra_field)
      end

      it 'handles nil prediction values safely' do
        nil_prediction = OpenStruct.new(
          problem: "test",
          answer: nil,
          explanation: "no answer"
        ).tap do |pred|
          pred.define_singleton_method(:to_h) do
            { problem: problem, answer: answer, explanation: explanation }
          end
        end

        result = DSPy::Teleprompt::Utils.send(
          :extract_output_fields_from_prediction,
          nil_prediction,
          BootstrapMath
        )

        expect(result).to eq({
          answer: nil,
          explanation: "no answer"
        })
      end

      it 'handles prediction objects that cannot be converted to hash' do
        broken_prediction = Object.new

        expect {
          DSPy::Teleprompt::Utils.send(
            :extract_output_fields_from_prediction,
            broken_prediction,
            BootstrapMath
          )
        }.to raise_error(NoMethodError, /undefined method `to_h'/)
      end
    end

    describe '.infer_signature_class' do
      it 'infers from DSPy::Example objects' do
        examples = [create_test_example("test", 1)]
        
        result = DSPy::Teleprompt::Utils.send(:infer_signature_class, examples)
        
        expect(result).to eq(BootstrapMath)
      end

      it 'infers from hash with signature_class' do
        examples = [{ signature_class: BootstrapMath, test: "data" }]
        
        result = DSPy::Teleprompt::Utils.send(:infer_signature_class, examples)
        
        expect(result).to eq(BootstrapMath)
      end

      it 'returns nil when cannot infer' do
        examples = [{ test: "data" }]
        
        result = DSPy::Teleprompt::Utils.send(:infer_signature_class, examples)
        
        expect(result).to be_nil
      end
    end

    describe '.default_metric_for_examples' do
      it 'creates metric for DSPy::Example objects' do
        examples = [create_test_example("test", 1)]
        
        metric = DSPy::Teleprompt::Utils.send(:default_metric_for_examples, examples)
        
        expect(metric).to be_a(Proc)
        # Use the exact expected values from the example (matches "Unknown problem" for "test")
        expected_prediction = { answer: 1, explanation: "Unknown problem" }
        expect(metric.call(examples.first, expected_prediction)).to be(true)
      end

      it 'returns nil for non-Example objects' do
        examples = [{ test: "data" }]
        
        metric = DSPy::Teleprompt::Utils.send(:default_metric_for_examples, examples)
        
        expect(metric).to be_nil
      end
    end
  end


  private

  def create_test_example(problem, answer)
    # Create expected explanation that matches what MockMathPredictor returns
    explanation = case problem
    when "2 + 3"
      "Add 2 and 3 to get 5"
    when "10 - 4"
      "Subtract 4 from 10 to get 6"
    when "3 × 7"
      "Multiply 3 by 7 to get 21"
    else
      "Unknown problem"
    end

    DSPy::Example.new(
      signature_class: BootstrapMath,
      input: { problem: problem },
      expected: { answer: answer, explanation: explanation },
      id: "test_#{problem.gsub(/\W/, '_')}"
    )
  end
end