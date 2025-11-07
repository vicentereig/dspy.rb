require 'spec_helper'
require 'tmpdir'

RSpec.describe 'ADE GEPA CLI' do
  SCRIPT_PATH = File.expand_path('../../../examples/ade_optimizer_gepa/main.rb', __dir__)

  before(:all) do
    @original_skip = ENV['DSPY_EXAMPLE_SKIP_AUTO_RUN']
    ENV['DSPY_EXAMPLE_SKIP_AUTO_RUN'] = '1'
    load SCRIPT_PATH
  end

  after(:all) do
    if @original_skip
      ENV['DSPY_EXAMPLE_SKIP_AUTO_RUN'] = @original_skip
    else
      ENV.delete('DSPY_EXAMPLE_SKIP_AUTO_RUN')
    end
  end

  around do |example|
    original_openai = ENV['OPENAI_API_KEY']
    ENV.delete('OPENAI_API_KEY')
    example.run
    if original_openai
      ENV['OPENAI_API_KEY'] = original_openai
    else
      ENV.delete('OPENAI_API_KEY')
    end
  end

  it 'accepts fully-qualified model ids without exiting' do
    options = ADEGEPAOptimizationDemo.parse_options(['--model', 'openai/gpt-4o-mini'])
    expect(options.model).to eq('openai/gpt-4o-mini')
  end

  it 'rejects providerless model ids' do
    expect do
      expect do
        ADEGEPAOptimizationDemo.parse_options(['--model', 'gpt4'])
      end.to raise_error(SystemExit)
    end.to output(/Invalid model 'gpt4'/).to_stderr
  end

  describe '#persist_results' do
    let(:options) do
      ADEGEPAOptimizationDemo::Options.new(
        limit: 10,
        max_metric_calls: 100,
        minibatch_size: 5,
        seed: 123,
        track_stats_path: nil,
        model: 'openai/gpt-4o-mini'
      )
    end

    let(:baseline_metrics) { ADEExampleGEPA::ExampleEvaluation.new(0.1, 0.2, 0.3, 0.4) }
    let(:optimized_metrics) { ADEExampleGEPA::ExampleEvaluation.new(0.5, 0.6, 0.7, 0.8) }
    let(:result_struct) { Struct.new(:metadata, :best_score_value, :history) }
    let(:result) do
      result_struct.new(
        { candidates: 3 },
        0.95,
        { total_trials: 7 }
      )
    end

    it 'stores summary and metrics under provider/model directory with timestamped filenames' do
      Dir.mktmpdir do |tmpdir|
        run_dir = File.join(tmpdir, 'results', 'openai', 'gpt_4o_mini')
        FileUtils.mkdir_p(run_dir)
        timestamp_prefix = '20240102030405'
        run_timestamp = Time.utc(2024, 1, 2, 3, 4, 5)

        summary_path, csv_path = ADEGEPAOptimizationDemo.send(
          :persist_results,
          run_dir,
          timestamp_prefix,
          run_timestamp,
          options,
          baseline_metrics,
          optimized_metrics,
          result
        )

        expect(summary_path).to eq(File.join(run_dir, "#{timestamp_prefix}_summary.json"))
        expect(csv_path).to eq(File.join(run_dir, "#{timestamp_prefix}_metrics.csv"))
        expect(File).to exist(summary_path)
        expect(File).to exist(csv_path)

        summary_data = JSON.parse(File.read(summary_path))
        expect(summary_data['model']).to eq('openai/gpt-4o-mini')
        expect(summary_data['max_metric_calls']).to eq(100)
      end
    end
  end
end
