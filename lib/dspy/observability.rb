# typed: false
# frozen_string_literal: true

begin
  require 'dspy/o11y'
rescue LoadError
  require 'sorbet-runtime'

  module DSPy
    class Observability
      class << self
        def register_configurator(*); end
        def configure!(*); false; end
        def enabled?; false; end
        def enable!(*); false; end
        def disable!(*); nil; end
        def start_span(*); nil; end
        def finish_span(*); nil; end
        def flush!; nil; end
        def reset!; nil; end
        def require_dependency(lib)
          require lib
        rescue LoadError
          raise
        end
      end
    end

    # Guard against double-loading with Zeitwerk/Rails autoloader
    # See: https://github.com/vicentereig/dspy.rb/issues/190
    unless defined?(DSPy::ObservationType)
      class ObservationType < T::Enum
        enums do
          Generation = new('generation')
          Agent = new('agent')
          Tool = new('tool')
          Chain = new('chain')
          Retriever = new('retriever')
          Embedding = new('embedding')
          Evaluator = new('evaluator')
          Span = new('span')
          Event = new('event')
        end

        def self.for_module_class(_module_class)
          Span
        end

        def langfuse_attribute
          ['langfuse.observation.type', serialize]
        end

        def langfuse_attributes
          { 'langfuse.observation.type' => serialize }
        end
      end
    end
  end
end
