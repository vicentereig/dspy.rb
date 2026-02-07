# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative 'types'
require_relative 'signatures'

module HtmlToMarkdown
  # Two-phase hierarchical parser for complex HTML documents
  #
  # Benefits over single-pass parsing:
  # - Avoids max_tokens limits by processing in chunks
  # - More reliable for complex documents
  # - Produces complete, accurate output
  #
  # Phase 1: Extract document outline (skeleton)
  # Phase 2: Fill each section with detailed content
  class HierarchicalParser
    extend T::Sig

    sig { void }
    def initialize
      @outline_parser = T.let(DSPy::Predict.new(ParseOutline), DSPy::Predict)
      @section_parser = T.let(DSPy::Predict.new(ParseSection), DSPy::Predict)
    end

    sig { params(html: String).returns(MarkdownDocument) }
    def parse(html)
      # Phase 1: Extract outline
      outline_result = @outline_parser.call(html: html)
      sections = outline_result.sections

      # Phase 2: Parse each section
      nodes = sections.map do |section|
        parse_section(section)
      end

      MarkdownDocument.new(nodes: nodes)
    end

    private

    sig { params(section: SkeletonSection).returns(ASTNode) }
    def parse_section(section)
      # For simple sections (headings, hr, code blocks), we can build directly
      case section.node_type
      when NodeType::Heading
        ASTNode.new(
          node_type: NodeType::Heading,
          text: section.text,
          level: section.level
        )
      when NodeType::HorizontalRule
        ASTNode.new(node_type: NodeType::HorizontalRule)
      when NodeType::CodeBlock
        ASTNode.new(
          node_type: NodeType::CodeBlock,
          text: section.text,
          language: section.language
        )
      else
        # For complex sections (paragraphs, lists, blockquotes), use LLM
        parse_complex_section(section)
      end
    end

    sig { params(section: SkeletonSection).returns(ASTNode) }
    def parse_complex_section(section)
      return empty_node(section.node_type) if section.section_html.empty?

      result = @section_parser.call(
        html: section.section_html,
        node_type: section.node_type.serialize
      )
      result.node
    end

    sig { params(node_type: NodeType).returns(ASTNode) }
    def empty_node(node_type)
      ASTNode.new(node_type: node_type)
    end
  end
end
