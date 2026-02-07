# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module HtmlToMarkdown
  class NodeType < T::Enum
    extend T::Sig

    enums do
      # Block elements
      Heading = new('heading')
      Paragraph = new('paragraph')
      CodeBlock = new('code_block')
      Blockquote = new('blockquote')
      HorizontalRule = new('horizontal_rule')
      List = new('list')
      ListItem = new('list_item')
      Table = new('table')
      TableRow = new('table_row')
      TableCell = new('table_cell')

      # Inline elements
      Text = new('text')
      Bold = new('bold')
      Italic = new('italic')
      Code = new('code')
      Link = new('link')
      Image = new('image')
      LineBreak = new('line_break')
      Strikethrough = new('strikethrough')

      # Extended
      FootnoteRef = new('footnote_ref')
      FootnoteDef = new('footnote_def')
      TaskListItem = new('task_list_item')
    end
  end

  class ASTNode < T::Struct
    extend T::Sig

    const :node_type, NodeType
    const :text, String, default: ""
    const :level, Integer, default: 0        # for headings (1-6)
    const :language, String, default: ""     # for code blocks
    const :url, String, default: ""          # for links/images
    const :alt, String, default: ""          # for images
    const :title, String, default: ""        # for links/images
    const :ordered, T::Boolean, default: false  # for lists
    const :checked, T::Boolean, default: false  # for task list items
    const :align, String, default: ""        # for table cells
    const :header, T::Boolean, default: false   # for table cells
    const :id, String, default: ""           # for footnotes
    const :children, T::Array[ASTNode], default: []
  end

  class MarkdownDocument < T::Struct
    extend T::Sig

    const :nodes, T::Array[ASTNode]
  end

  # Skeleton section for hierarchical parsing (Phase 1 output)
  # Contains just enough info to identify block type + raw HTML for phase 2
  #
  # Fields:
  # - node_type: Block element type (heading, paragraph, code_block, list, blockquote, horizontal_rule)
  # - text: Text content for headings and code blocks
  # - level: Heading level 1-6 (only for headings)
  # - language: Programming language (only for code_block)
  # - ordered: True for ordered lists, false for unordered
  # - section_html: Raw HTML for detailed parsing in phase 2
  class SkeletonSection < T::Struct
    extend T::Sig

    const :node_type, NodeType
    const :text, String, default: ""
    const :level, Integer, default: 0
    const :language, String, default: ""
    const :ordered, T::Boolean, default: false
    const :section_html, String, default: ""
  end
end
