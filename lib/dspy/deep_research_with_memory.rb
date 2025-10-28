# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class DeepResearchWithMemory < DSPy::Module
    extend T::Sig

    DEFAULT_MEMORY_LIMIT = 5

    class MemoryEntry < T::Struct
      const :brief, String
      const :report, String
      const :citations, T::Array[String]
      const :sections, T::Array[DSPy::DeepResearch::Module::SectionResult]
    end

    sig do
      params(
        deep_research_module: DSPy::Module,
        memory_limit: Integer
      ).void
    end
    def initialize(
      deep_research_module: DSPy::DeepResearch::Module.new,
      memory_limit: DEFAULT_MEMORY_LIMIT
    )
      super()

      validate_memory_limit!(memory_limit)

      @deep_research_module = T.let(deep_research_module, DSPy::Module)
      @memory_limit = T.let(memory_limit, Integer)
      @memory_entries = T.let([], T::Array[MemoryEntry])
    end

    sig { returns(DSPy::Module) }
    attr_reader :deep_research_module

    sig { returns(Integer) }
    def memory_limit
      @memory_limit
    end

    sig { returns(T::Array[[String, DSPy::Module]]) }
    def named_predictors
      [["deep_research", @deep_research_module]]
    end

    sig { override.returns(T::Array[DSPy::Module]) }
    def predictors
      [@deep_research_module]
    end

    sig { params(instruction: String).returns(DeepResearchWithMemory) }
    def with_instruction(instruction)
      updated_inner = if @deep_research_module.respond_to?(:with_instruction)
        @deep_research_module.with_instruction(instruction)
      else
        @deep_research_module
      end

      clone_with(
        deep_research_module: updated_inner,
        memory_entries: deep_dup_memory
      )
    end

    sig { params(examples: T::Array[DSPy::FewShotExample]).returns(DeepResearchWithMemory) }
    def with_examples(examples)
      updated_inner = if @deep_research_module.respond_to?(:with_examples)
        @deep_research_module.with_examples(examples)
      else
        @deep_research_module
      end

      clone_with(
        deep_research_module: updated_inner,
        memory_entries: deep_dup_memory
      )
    end

    sig do
      override
        .params(input_values: T.untyped)
        .returns(DSPy::DeepResearch::Module::Result)
    end
    def forward_untyped(**input_values)
      brief = input_values[:brief]
      unless brief.is_a?(String)
        raise ArgumentError, "DeepResearchWithMemory expects keyword argument :brief"
      end

      memory_snapshot = input_values.key?(:memory) ? input_values[:memory] : serialized_memory

      inner_input = input_values.merge(memory: memory_snapshot)

      result = T.cast(@deep_research_module.call(**inner_input), DSPy::DeepResearch::Module::Result)

      append_memory_entry(brief, result)

      result
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def memory
      @memory_entries.map do |entry|
        {
          brief: entry.brief,
          report: entry.report,
          citations: entry.citations.dup,
          sections: entry.sections.dup
        }
      end
    end

    private

    sig { params(memory_limit: Integer).void }
    def validate_memory_limit!(memory_limit)
      if memory_limit.nil? || memory_limit <= 0
        raise ArgumentError, "memory_limit must be greater than zero"
      end
    end

    sig do
      params(
        deep_research_module: DSPy::Module,
        memory_entries: T::Array[MemoryEntry]
      ).returns(DeepResearchWithMemory)
    end
    def clone_with(deep_research_module:, memory_entries:)
      clone = self.class.new(
        deep_research_module: deep_research_module,
        memory_limit: @memory_limit
      )
      clone.instance_variable_set(:@memory_entries, memory_entries)
      clone
    end

    sig { returns(T::Array[MemoryEntry]) }
    def deep_dup_memory
      @memory_entries.map do |entry|
        MemoryEntry.new(
          brief: entry.brief,
          report: entry.report,
          citations: entry.citations.dup,
          sections: entry.sections.dup
        )
      end
    end

    sig { void }
    def trim_memory!
      while @memory_entries.length > @memory_limit
        @memory_entries.shift
      end
    end

    sig do
      params(
        brief: String,
        result: DSPy::DeepResearch::Module::Result
      ).void
    end
    def append_memory_entry(brief, result)
      entry = MemoryEntry.new(
        brief: brief,
        report: result.report,
        citations: Array(result.citations).compact.map(&:to_s),
        sections: Array(result.sections).dup
      )

      @memory_entries << entry
      trim_memory!

      DSPy.event(
        "deep_research.memory.updated",
        size: @memory_entries.length,
        last_brief: brief,
        memory_limit: @memory_limit,
        last_citation_count: entry.citations.length
      )
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialized_memory
      memory
    end
  end
end
