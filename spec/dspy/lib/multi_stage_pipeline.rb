# Outline signature for creating article structure
require 'sorbet-runtime'

# Use original class name for test compatibility
class Outline < DSPy::SorbetSignature
  description "Outline a thorough overview of a topic."

  input do |builder|
    builder.const :topic, String, description: "The topic to outline"
  end

  output do |builder|
    builder.const :title, String, description: "The title of the article"
    builder.const :sections, T::Array[String], description: "A list of section titles"
    builder.const :section_subheadings, T::Hash[String, T::Array[String]],
      description: "Mapping from section headings to subheadings"
  end
end

# DraftSection signature for creating content for a section
class DraftSection < DSPy::SorbetSignature
  description "Draft a top-level section of an article."

  input do |builder|
    builder.const :topic, String, description: "The article topic"
    builder.const :section_heading, String, description: "The section heading"
    builder.const :section_subheadings, T::Array[String], description: "List of subheadings for this section"
  end

  output do |builder|
    builder.const :content, String, description: "Markdown-formatted section content"
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
class ArticleDrafter < DSPy::SorbetModule
  def initialize
    @build_outline = DSPy::SorbetChainOfThought.new(Outline)
    @draft_section = DSPy::SorbetChainOfThought.new(DraftSection)
  end

  def forward(topic)
    # First, build the outline
    outline = @build_outline.call(topic: topic)

    # Then, draft each section
    sections = []

    (outline.section_subheadings || {}).each do |heading, subheadings|
      section_heading = "## #{heading}"
      formatted_subheadings = [subheadings].flatten.map { |subheading| "### #{subheading}" }

      # Draft this section
      section = @draft_section.call(
        topic: outline.title,
        section_heading: section_heading,
        section_subheadings: formatted_subheadings
      )

      sections << section
    end

    DraftArticle.new(title: outline.title, sections: sections)
  end
end
