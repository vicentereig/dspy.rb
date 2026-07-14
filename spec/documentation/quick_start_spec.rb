# frozen_string_literal: true

require 'spec_helper'
require 'bundler'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tempfile'
require 'tmpdir'

# The examples intentionally keep the extracted source and all of its boundary
# checks together so drift is visible in one place.
# rubocop:disable Metrics/BlockLength
RSpec.describe 'the canonical Quick Start' do
  repository_root = File.expand_path('../..', __dir__)
  quick_start_path = File.expand_path('../../docs/src/getting-started/quick-start.md', __dir__)
  quick_start = File.read(quick_start_path, encoding: 'UTF-8')

  let(:repository_root) { repository_root }

  def extract_fence(source, marker, language)
    match = source.match(/<!-- #{Regexp.escape(marker)} -->\s*```#{language}\n(.*?)\n```/m)
    raise "Missing #{marker} #{language} fence" unless match

    match[1]
  end

  def copy_shipped_package(gemspec_name, destination)
    specification = Gem::Specification.load(File.join(repository_root, gemspec_name))

    specification.files.grep(%r{\Alib/}).each do |relative_path|
      source = File.join(repository_root, relative_path)
      target = File.join(destination, relative_path)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(source, target)
    end
  end

  def external_dependency_paths
    specifications = Bundler.load.specs
    specifications.select { |specification| specification.source.is_a?(Bundler::Source::Rubygems) }
                  .flat_map(&:full_require_paths)
                  .uniq
  end

  def packaged_subprocess_environment(package_paths)
    {
      'DSPY_DISABLE_OBSERVABILITY' => 'true',
      'DSPY_LOG' => File::NULL,
      'HOME' => ENV.fetch('HOME'),
      'LANG' => ENV.fetch('LANG', 'C.UTF-8'),
      'PATH' => ENV.fetch('PATH'),
      'RACK_ENV' => 'test',
      'RUBYLIB' => (package_paths + external_dependency_paths).join(File::PATH_SEPARATOR)
    }
  end

  def run_packaged_subprocess(script, package_paths, working_directory)
    Open3.capture3(
      packaged_subprocess_environment(package_paths),
      RbConfig.ruby,
      '--disable-gems',
      '-e',
      script,
      chdir: working_directory,
      unsetenv_others: true
    )
  end

  let(:gemfile) { extract_fence(quick_start, 'quick-start-gemfile', 'ruby') }
  let(:program) { extract_fence(quick_start, 'quick-start-program', 'ruby') }

  # This Gemfile parser runs under the repository bundle. The isolated subprocess
  # example below separately owns core-versus-adapter package-boundary coverage.
  it 'names the exact core and adapter dependencies in a valid Gemfile' do
    Tempfile.create('quick-start-gemfile') do |file|
      file.write(gemfile)
      file.flush

      dependencies = Bundler::Dsl.evaluate(file.path, nil, {}).dependencies.map(&:name)
      expect(dependencies).to eq(%w[dspy dspy-openai])
    end

    adapter = DSPy::LM::AdapterFactory::ADAPTER_MAP.fetch('openai')
    expect(adapter.fetch(:gem_name)).to eq('dspy-openai')
  end

  it 'preserves the adapter and API-key boundaries in isolated packaged source trees' do
    Dir.mktmpdir('dspy-quick-start-packages') do |directory|
      core = File.join(directory, 'core')
      adapter = File.join(directory, 'adapter')
      toon = File.join(directory, 'toon')
      copy_shipped_package('dspy.gemspec', core)
      copy_shipped_package('dspy-openai.gemspec', adapter)
      copy_shipped_package('sorbet-toon.gemspec', toon)

      core_script = <<~RUBY
        repository_lib = #{File.join(repository_root, 'lib').inspect}
        abort 'repository lib leaked into load path' if $LOAD_PATH.any? { |path| File.expand_path(path) == repository_lib }
        require 'dspy'
        loaded_core = $LOADED_FEATURES.find { |path| path.end_with?('/dspy.rb') }
        packaged_core = #{File.join(core, 'lib/dspy.rb').inspect}
        abort 'core did not load from packaged tree' unless File.realpath(loaded_core) == File.realpath(packaged_core)

        begin
          DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test-key')
        rescue DSPy::LM::MissingAdapterError => error
          abort 'missing adapter guidance omitted dspy-openai' unless error.message.include?('dspy-openai')
          puts 'core-only: missing adapter'
        else
          abort 'core-only package unexpectedly loaded an OpenAI adapter'
        end
      RUBY

      core_paths = [File.join(core, 'lib'), File.join(toon, 'lib')]
      stdout, stderr, status = run_packaged_subprocess(core_script, core_paths, directory)
      expect(status).to be_success, "#{stdout}\n#{stderr}"
      expect(stdout).to include('core-only: missing adapter')

      adapter_script = <<~RUBY
        repository_lib = #{File.join(repository_root, 'lib').inspect}
        abort 'repository lib leaked into load path' if $LOAD_PATH.any? { |path| File.expand_path(path) == repository_lib }
        require 'dspy'

        begin
          DSPy::LM.new('openai/gpt-4o-mini', api_key: nil)
        rescue DSPy::LM::MissingAPIKeyError => error
          abort 'missing key guidance omitted OPENAI_API_KEY' unless error.message.include?('OPENAI_API_KEY')
        else
          abort 'adapter package accepted a missing OpenAI key'
        end

        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test-key')
        expected = 'DSPy::OpenAI::LM::Adapters::OpenAIAdapter'
        abort 'wrong packaged adapter loaded' unless lm.adapter.class.name == expected
        adapter_entrypoint = #{File.join(adapter, 'lib/dspy/openai.rb').inspect}
        loaded_adapter = $LOADED_FEATURES.find { |path| path.end_with?('/dspy/openai.rb') }
        abort 'adapter did not load from packaged tree' unless File.realpath(loaded_adapter) == File.realpath(adapter_entrypoint)
        puts 'core+adapter: missing key and adapter class verified'
      RUBY

      paths = [File.join(core, 'lib'), File.join(adapter, 'lib'), File.join(toon, 'lib')]
      stdout, stderr, status = run_packaged_subprocess(adapter_script, paths, directory)
      expect(status).to be_success, "#{stdout}\n#{stderr}"
      expect(stdout).to include('core+adapter: missing key and adapter class verified')
    end
  end

  it 'documents the exact install, key, filename, and run commands' do
    expect(extract_fence(quick_start, 'quick-start-install-command', 'bash')).to eq('bundle install')
    expect(extract_fence(quick_start, 'quick-start-api-key-command', 'bash')).to eq(
      'export OPENAI_API_KEY=sk-your-key-here'
    )
    expect(quick_start).to include('Save this exact program as `classify.rb`')
    expect(extract_fence(quick_start, 'quick-start-run-command', 'bash')).to eq(
      'bundle exec ruby classify.rb'
    )
  end

  it 'executes the exact program without network access and returns declared Ruby types' do
    response = DSPy::LM::Response.new(
      content: '{"sentiment":"positive","confidence":0.73}',
      metadata: { provider: 'test', model: 'test-model' }
    )
    adapter_class = stub_const('QuickStartDocumentationAdapter', Class.new(DSPy::LM::Adapter) do
      define_method(:chat) { |**_arguments| response }
    end)
    adapter = adapter_class.new(model: 'test-model', api_key: 'test-key')
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(adapter)

    sandbox = Module.new
    result_key = :dspy_quick_start_result
    previous_key = ENV['OPENAI_API_KEY']
    ENV['OPENAI_API_KEY'] = 'test-key'
    WebMock.reset!

    expect do
      sandbox.module_eval("#{program}\nThread.current[:#{result_key}] = result", __FILE__, __LINE__)
    end.to output("positive\n0.73\n").to_stdout

    result = Thread.current[result_key]
    sentiment_class = sandbox.const_get(:Classify).const_get(:Sentiment)
    expect(result.sentiment).to be_a(sentiment_class)
    expect(result.confidence).to be_a(Float)
    expect(a_request(:any, /.*/)).not_to have_been_made
  ensure
    Thread.current[result_key] = nil
    previous_key.nil? ? ENV.delete('OPENAI_API_KEY') : ENV['OPENAI_API_KEY'] = previous_key
  end

  it 'raises KeyError before adapter initialization when the documented key is missing' do
    previous_key = ENV.delete('OPENAI_API_KEY')
    expect(DSPy::LM::AdapterFactory).not_to receive(:create)

    expect { Module.new.module_eval(program, __FILE__, __LINE__) }
      .to raise_error(KeyError, /OPENAI_API_KEY/)
  ensure
    ENV['OPENAI_API_KEY'] = previous_key if previous_key
  end

  it 'keeps generated LLM references aligned with the canonical program and setup' do
    llms = File.read(File.expand_path('../../docs/src/llms.txt.erb', __dir__), encoding: 'UTF-8')
    llms_full = File.read(File.expand_path('../../docs/src/llms-full.txt.erb', __dir__), encoding: 'UTF-8')

    [llms, llms_full].each do |reference|
      expect(reference).to include(program)
      expect(reference).to include('dspy-openai')
      expect(reference).to include('bundle install')
      expect(reference).to include('export OPENAI_API_KEY=sk-your-key-here')
      expect(reference).to include('bundle exec ruby classify.rb')
    end
  end

  it 'contains no framework-specific logging constants in the canonical program' do
    expect { RubyVM::InstructionSequence.compile(program, 'classify.rb') }.not_to raise_error
    expect(program).not_to match(/Rails(?:\.root)?|Dry\.Logger/)
  end
end
# rubocop:enable Metrics/BlockLength
