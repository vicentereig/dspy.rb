
# Outline signature for creating article structure
module Types
  include Dry.Types()
end

class Outline < DSPy::Signature
  description "Outline a thorough overview of a topic."
  input do
    required(:topic).value('string')
  end
  output do
    required(:title).value(:string)
    required(:sections).value(Types::Array.of(Types::String)).meta(description: 'a list of section titles')
    required(:section_subheadings).value(Types::Hash.schema(section: Types::String, subheading: Types::Array.of(Types::String))).meta(
      description: 'mapping from section headings to subheadings'
    )
  end
end

# DraftSection signature for creating content for a section
class DraftSection < DSPy::Signature
  description "Draft a top-level section of an article."

  input do
    required(:topic).value(:string)
    required(:section_heading).value(:string)
    required(:section_subheadings).value(Types::Array.of(Types::String))
  end

  output do
    required(:content).value(:string).meta(description: 'markdown-formatted section')
  end
end

class DraftArticle
  attr_reader :title, :sections

  def initialize(title:, sections:)
    @title = title
    @sections = sections
  end
end

# DraftArticle module that composes the pipeline
class ArticleDrafter < DSPy::Module
  def initialize
    @build_outline = DSPy::ChainOfThought.new(Outline)
    @draft_section = DSPy::ChainOfThought.new(DraftSection)
  end

  def forward(topic)
    # First, build the outline
    outline = @build_outline.call(topic: topic)
    # Then, draft each section
    sections = []

    (outline[:section_subheadings] || {}).each do |heading, subheadings|
      section_heading = "## #{heading}"
      formatted_subheadings = [subheadings].flatten.map { |subheading| "### #{subheading}" }

      # Draft this section
      section = @draft_section.call(
        topic: outline[:title],
        section_heading: section_heading,
        section_subheadings: formatted_subheadings
      )

      sections << section
    end

    DraftArticle.new(title: outline[:title], sections: sections)
  end
end
