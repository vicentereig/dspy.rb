# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative 'types'

module HtmlToMarkdown
  class MarkdownRenderer
    extend T::Sig

    sig { params(document: MarkdownDocument).returns(String) }
    def render(document)
      document.nodes.map { |node| render_block(node) }.join("\n\n")
    end

    private

    sig { params(node: ASTNode).returns(String) }
    def render_block(node)
      case node.node_type
      when NodeType::Heading
        render_heading(node)
      when NodeType::Paragraph
        render_children(node)
      when NodeType::CodeBlock
        render_code_block(node)
      when NodeType::Blockquote
        render_blockquote(node)
      when NodeType::HorizontalRule
        '---'
      when NodeType::List
        render_list(node)
      when NodeType::Image
        render_image(node)
      else
        render_inline(node)
      end
    end

    sig { params(node: ASTNode).returns(String) }
    def render_inline(node)
      case node.node_type
      when NodeType::Text
        node.text
      when NodeType::Bold
        content = node.children.empty? ? node.text : render_children(node)
        "**#{content}**"
      when NodeType::Italic
        content = node.children.empty? ? node.text : render_children(node)
        "*#{content}*"
      when NodeType::Code
        "`#{node.text}`"
      when NodeType::Link
        render_link(node)
      when NodeType::Image
        render_image(node)
      when NodeType::Strikethrough
        content = node.children.empty? ? node.text : render_children(node)
        "~~#{content}~~"
      when NodeType::LineBreak
        "  \n"
      else
        render_children(node)
      end
    end

    sig { params(node: ASTNode).returns(String) }
    def render_heading(node)
      level = node.level.positive? ? node.level : 1
      prefix = '#' * level
      # Use text directly if no children, otherwise render children
      content = node.children.empty? ? node.text : render_children(node)
      "#{prefix} #{content}"
    end

    sig { params(node: ASTNode).returns(String) }
    def render_code_block(node)
      lang = node.language || ''
      code = node.text || ''
      "```#{lang}\n#{code}\n```"
    end

    sig { params(node: ASTNode).returns(String) }
    def render_blockquote(node)
      content = render_children(node)
      content.lines.map { |line| "> #{line.chomp}" }.join("\n")
    end

    sig { params(node: ASTNode).returns(String) }
    def render_list(node)
      return '' unless node.children

      ordered = node.ordered == true
      node.children.each_with_index.map do |item, index|
        marker = ordered ? "#{index + 1}." : '-'
        content = render_children(item)
        "#{marker} #{content}"
      end.join("\n")
    end

    sig { params(node: ASTNode).returns(String) }
    def render_link(node)
      text = render_children(node)
      url = node.url || ''
      "[#{text}](#{url})"
    end

    sig { params(node: ASTNode).returns(String) }
    def render_image(node)
      alt = node.alt || ''
      url = node.url || ''
      "![#{alt}](#{url})"
    end

    sig { params(node: ASTNode).returns(String) }
    def render_children(node)
      return '' unless node.children

      node.children.map { |child| render_inline(child) }.join
    end
  end
end
