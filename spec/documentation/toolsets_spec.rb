# frozen_string_literal: true

require 'spec_helper'
require 'bundler'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe 'the packaged TextProcessingToolset example' do
  repository_root = File.expand_path('../..', __dir__)
  guide_path = File.join(repository_root, 'docs/src/core-concepts/toolsets.md')
  guide = File.read(guide_path, encoding: 'UTF-8')
  example = guide.match(
    /<!-- toolsets-text-processing-example -->\s*```ruby\n(.*?)\n```/m
  )&.captures&.first

  raise 'Missing canonical TextProcessingToolset example' unless example

  let(:repository_root) { repository_root }
  let(:example) { example }

  def runtime_dependency_paths(root_specification)
    available = Bundler.load.specs.group_by(&:name)
    pending = root_specification.runtime_dependencies.dup
    visited = {}
    paths = []

    until pending.empty?
      dependency = pending.shift
      next if visited[dependency.name]

      specification = available.fetch(dependency.name).find do |candidate|
        dependency.match?(candidate.name, candidate.version)
      end
      raise "Unresolved runtime dependency: #{dependency}" unless specification

      visited[dependency.name] = true
      paths.concat(specification.full_require_paths)
      pending.concat(specification.runtime_dependencies)
    end

    repository_lib = File.join(repository_root, 'lib')
    paths.uniq.reject { |path| File.expand_path(path) == repository_lib }
  end

  it 'ships the direct-load dependency chain and runs the exact example in a clean consumer process' do
    specification = Gem::Specification.load(File.join(repository_root, 'dspy.gemspec'))
    required_files = %w[
      lib/dspy/tools/base.rb
      lib/dspy/tools/toolset.rb
      lib/dspy/tools/text_processing_toolset.rb
      lib/dspy/type_system/sorbet_json_schema.rb
      lib/dspy/mixins/type_coercion.rb
    ]
    expect(specification.files).to include(*required_files)

    Dir.mktmpdir('dspy-toolsets-package') do |directory|
      specification.files.grep(%r{\Alib/}).each do |relative_path|
        source = File.join(repository_root, relative_path)
        target = File.join(directory, relative_path)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
      end

      packaged_feature = File.join(directory, 'lib/dspy/tools/text_processing_toolset.rb')
      consumer = <<~RUBY
        repository_lib = #{File.join(repository_root, 'lib').inspect}
        abort 'repository lib leaked into load path' if $LOAD_PATH.any? { |path| File.expand_path(path) == repository_lib }
        abort 'TextProcessingToolset was already defined' if defined?(DSPy::Tools::TextProcessingToolset)

        require 'socket'
        deny_network = Module.new do
          def new(*) = raise('network access attempted')
          def open(*) = raise('network access attempted')
          def tcp(*) = raise('network access attempted')
          def udp(*) = raise('network access attempted')
        end
        Socket.singleton_class.prepend(deny_network)
        TCPSocket.singleton_class.prepend(deny_network)
        UDPSocket.singleton_class.prepend(deny_network)

        #{example}

        loaded_feature = $LOADED_FEATURES.find { |path| path.end_with?('/dspy/tools/text_processing_toolset.rb') }
        expected_feature = #{packaged_feature.inspect}
        abort 'feature did not load from packaged tree' unless File.realpath(loaded_feature) == File.realpath(expected_feature)
      RUBY

      environment = {
        'HOME' => directory,
        'LANG' => ENV.fetch('LANG', 'C.UTF-8'),
        'PATH' => '',
        'RUBYLIB' => ([File.join(directory, 'lib')] + runtime_dependency_paths(specification)).join(File::PATH_SEPARATOR),
        'TMPDIR' => directory
      }
      stdout, stderr, status = Open3.capture3(
        environment,
        RbConfig.ruby,
        '--disable-gems',
        '-e',
        consumer,
        chdir: directory,
        unsetenv_others: true
      )

      expected_names = %w[
        text_grep
        text_wc
        text_rg
        text_extract_lines
        text_filter_lines
        text_unique_lines
        text_sort_lines
        text_summarize_text
      ].join(',')
      expect(status).to be_success, "#{stdout}\n#{stderr}"
      expect(stderr).to be_empty
      expect(stdout).to eq("#{expected_names}\nLines: 2, Words: 3, Characters: 13\n")
    end
  end
end
