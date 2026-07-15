# frozen_string_literal: true

require 'spec_helper'
require 'dspy/o11y/langfuse'

# These examples execute the exact marked fences from the canonical guides so a
# prose edit cannot silently leave the tested program behind.
# rubocop:disable Metrics/BlockLength
RSpec.describe 'long-page runnable examples' do
  ROOT = File.expand_path('../..', __dir__)

  def extract_program(relative_path, marker)
    source = File.read(File.join(ROOT, relative_path), encoding: 'UTF-8')
    match = source.match(/<!-- #{Regexp.escape(marker)} -->\s*```ruby\n(.*?)\n```/m)
    raise "Missing #{marker} Ruby fence in #{relative_path}" unless match

    match[1]
  end

  def preserve_environment(*names)
    previous = names.to_h { |name| [name, ENV[name]] }
    yield
  ensure
    previous.each do |name, value|
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end
  end

  it 'runs concurrent predictions with bounded overlap, ordered results, and isolated failures' do
    program = extract_program(
      'docs/src/advanced/concurrent-predictions.md',
      'concurrent-predictions-program'
    )
    response = DSPy::LM::Response.new(
      content: '{"sentiment":"positive"}',
      metadata: { provider: 'test', model: 'test-model' }
    )
    state = { active: 0, max_active: 0 }
    mutex = Mutex.new

    adapter_class = stub_const('ConcurrentPredictionsDocumentationAdapter', Class.new(DSPy::LM::Adapter) do
      define_method(:chat) do |messages:, **_arguments|
        content = messages.last.fetch(:content)
        mutex.synchronize do
          state[:active] += 1
          state[:max_active] = [state[:max_active], state[:active]].max
        end
        sleep 0.02
        raise 'forced adapter failure' if content.include?('FAIL')

        response
      ensure
        mutex.synchronize { state[:active] -= 1 }
      end
    end)
    adapter = adapter_class.new(model: 'test-model', api_key: 'test-key')
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(adapter)

    result_key = :dspy_concurrent_predictions_example
    sandbox = Module.new
    WebMock.reset!

    preserve_environment('OPENAI_API_KEY') do
      ENV['OPENAI_API_KEY'] = 'test-key'
      expect do
        sandbox.module_eval(
          "#{program}\nThread.current[:#{result_key}] = [batch, results]",
          __FILE__,
          __LINE__
        )
      end.to output(
        "Excellent: positive\nNeeds work: positive\nShip it: positive\n"
      ).to_stdout

      batch, results = Thread.current[result_key]
      expect(results.map(&:input)).to eq(['Excellent', 'Needs work', 'Ship it'])
      expect(results.map { |item| item.prediction.sentiment }).to eq(%w[positive positive positive])
      expect(state[:max_active]).to be >= 2

      mixed = batch.call(['Alpha', 'FAIL', 'Omega'])
      expect(mixed.map(&:input)).to eq(['Alpha', 'FAIL', 'Omega'])
      expect(mixed.values_at(0, 2)).to all(satisfy { _1.error.nil? && _1.prediction.sentiment == 'positive' })
      expect(mixed[1].prediction).to be_nil
      expect(mixed[1].error).to be_a(RuntimeError)
      expect(mixed[1].error.message).to eq('forced adapter failure')
      expect { batch.call(%w[one two three four]) }.to raise_error(ArgumentError, /at most 3 inputs/)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  ensure
    Thread.current[result_key] = nil
  end

  it 'runs the lifecycle callback example and verifies its failure path' do
    program = extract_program(
      'docs/src/advanced/module-lifecycle-callbacks.md',
      'module-lifecycle-callbacks-program'
    )
    result_key = :dspy_module_lifecycle_callbacks_example
    sandbox = Module.new
    WebMock.reset!

    expect do
      sandbox.module_eval(
        "#{program}\nThread.current[:#{result_key}] = [normalizer, result]",
        __FILE__,
        __LINE__
      )
    end.to output(
      "What is a typed module?\nbefore -> around_before -> forward -> around_after -> after\n"
    ).to_stdout

    normalizer, result = Thread.current[result_key]
    expect(result).to eq('What is a typed module?')
    expect(normalizer.events).to eq(%i[before around_before forward around_after after])

    failing = sandbox.const_get(:NormalizedQuestion).new
    expect { failing.call(question: '  ') }.to raise_error(ArgumentError, 'question cannot be blank')
    expect(failing.events).to eq(%i[before around_before forward around_error])
    expect(a_request(:any, /.*/)).not_to have_been_made
  ensure
    Thread.current[result_key] = nil
  end

  it 'runs score reporting through the real event and exporter lifecycle without HTTP' do
    program = extract_program(
      'docs/src/production/score-reporting.md',
      'score-reporting-program'
    )
    exporter_class = DSPy::Observability::Adapters::Langfuse::ScoresExporter
    exported = Queue.new
    allow(exporter_class).to receive(:configure).and_wrap_original do |method, **arguments|
      exporter = method.call(**arguments)
      allow(exporter).to receive(:export).and_wrap_original do |export_method, event|
        exported << event
        export_method.call(event)
      end
      allow(exporter).to receive(:send_to_langfuse)
      exporter
    end

    result_key = :dspy_score_reporting_example
    sandbox = Module.new
    previous_registry = DSPy.instance_variable_get(:@event_registry)
    DSPy.instance_variable_set(:@event_registry, nil)
    DSPy.events
    WebMock.reset!

    preserve_environment('LANGFUSE_PUBLIC_KEY', 'LANGFUSE_SECRET_KEY', 'LANGFUSE_HOST') do
      ENV['LANGFUSE_PUBLIC_KEY'] = 'pk-test'
      ENV['LANGFUSE_SECRET_KEY'] = 'sk-test'
      ENV['LANGFUSE_HOST'] = 'https://langfuse.invalid'

      expect do
        sandbox.module_eval(
          "#{program}\nThread.current[:#{result_key}] = [score, observed_scores, exporter]",
          __FILE__,
          __LINE__
        )
      end.to output(
        "accuracy=0.95 trace=evaluation-run-42\nevents=1\n"
      ).to_stdout

      score, observed_scores, exporter = Thread.current[result_key]
      sent = exported.pop(true)
      expect(score).to be_a(DSPy::Scores::ScoreEvent)
      expect(observed_scores).to contain_exactly(include(
        score_id: score.id,
        score_name: 'accuracy',
        score_value: 0.95,
        trace_id: 'evaluation-run-42'
      ))
      expect(sent.id).to eq(score.id)
      expect(exporter).not_to be_running
      expect(exported).to be_empty
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  ensure
    Thread.current[result_key] = nil
    DSPy.instance_variable_set(:@event_registry, previous_registry)
  end
end
# rubocop:enable Metrics/BlockLength
