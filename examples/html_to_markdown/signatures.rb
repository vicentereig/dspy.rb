# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require_relative 'types'

module HtmlToMarkdown
  # ==========================================================================
  # HIERARCHICAL PARSING (Two-Phase Approach)
  # ==========================================================================
  # Phase 1: Extract document outline (skeleton structure)
  # Phase 2: Fill each section with full content
  #
  # Benefits:
  # - Avoids max_tokens by processing in chunks
  # - More reliable for complex documents
  # - Produces complete, accurate output

  # Phase 1: Extract the document skeleton
  class ParseOutline < DSPy::Signature
    description 'Extract block-level structure from HTML as a flat list of skeleton sections.'

    input do
      const :html, String, description: 'Raw HTML content to extract outline from'
    end

    output do
      const :sections, T::Array[SkeletonSection], description: 'Flat list of block-level sections (headings, paragraphs, code blocks, lists, blockquotes, hr)'
    end
  end

  # Phase 2: Parse a single section into full AST
  class ParseSection < DSPy::Signature
    description 'Parse an HTML section into a complete AST node with inline formatting and nested structures.'

    input do
      const :html, String, description: 'HTML content of this section to parse'
      const :node_type, String, description: 'Expected block type: heading, paragraph, list, code_block, blockquote, etc.'
    end

    output do
      const :node, ASTNode, description: 'Complete AST node with text content and children (bold, italic, links, nested items)'
    end
  end

  # ==========================================================================
  # SINGLE-PASS APPROACHES
  # ==========================================================================

  # Approach A: Structured AST output
  # Converts HTML to a typed Markdown AST that can be validated and rendered
  class ParseHtmlToAst < DSPy::Signature
    description <<~DESC
      Parse HTML content into a Markdown Abstract Syntax Tree (AST).

      Convert HTML elements to their Markdown AST node equivalents:
      - <h1>-<h6> -> Heading node with level 1-6
      - <p> -> Paragraph node with inline children
      - <strong> or <b> -> Bold node
      - <em> or <i> -> Italic node
      - <code> -> Code node (inline)
      - <pre><code> -> CodeBlock node with optional language
      - <a href="url"> -> Link node with url and text children
      - <img src="url" alt="text"> -> Image node
      - <ul> or <ol> -> List node (ordered: true/false)
      - <li> -> ListItem node
      - <blockquote> -> Blockquote node
      - <hr> -> HorizontalRule node
      - <del> or <s> -> Strikethrough node

      Structure rules:
      - Block elements (Heading, Paragraph, CodeBlock, List, Blockquote, HorizontalRule) are top-level nodes
      - Inline elements (Text, Bold, Italic, Code, Link, Image, Strikethrough) appear as children of block elements
      - Preserve text content exactly, including whitespace
      - Nested structures (lists within lists, formatting within formatting) use the children array
    DESC

    input do
      const :html, String, description: 'Raw HTML content to parse into Markdown AST'
    end

    output do
      const :document, MarkdownDocument, description: 'Parsed Markdown AST with typed nodes'
    end
  end

  # Approach B: Direct string conversion
  # Converts HTML directly to Markdown string without intermediate AST
  class ConvertHtmlToMarkdown < DSPy::Signature
    description <<~DESC
      Convert HTML content directly to Markdown string format.

      Apply standard Markdown conversions:
      - Headers: <h1> -> # , <h2> -> ## , etc.
      - Bold: <strong> or <b> -> **text**
      - Italic: <em> or <i> -> *text*
      - Inline code: <code> -> `code`
      - Code blocks: <pre><code class="language-X"> -> ```X\\ncode\\n```
      - Links: <a href="url">text</a> -> [text](url)
      - Images: <img src="url" alt="text"> -> ![text](url)
      - Unordered lists: <ul><li> -> - item
      - Ordered lists: <ol><li> -> 1. item
      - Blockquotes: <blockquote> -> > text
      - Horizontal rules: <hr> -> ---
      - Strikethrough: <del> or <s> -> ~~text~~

      Preserve:
      - Text content exactly as written
      - Paragraph breaks between block elements
      - Proper nesting of formatting (bold within italic, etc.)
    DESC

    input do
      const :html, String, description: 'Raw HTML content to convert to Markdown'
    end

    output do
      const :markdown, String, description: 'Converted Markdown string'
    end
  end
end
