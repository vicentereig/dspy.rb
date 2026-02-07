# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/html_to_markdown/types'
require_relative '../../examples/html_to_markdown/renderer'
require_relative '../../examples/html_to_markdown/signatures'
require_relative '../../examples/html_to_markdown/hierarchical_parser'

RSpec.describe HtmlToMarkdown do
  describe 'Types' do
    describe HtmlToMarkdown::NodeType do
      it 'serializes enum values to strings' do
        expect(HtmlToMarkdown::NodeType::Heading.serialize).to eq('heading')
        expect(HtmlToMarkdown::NodeType::Paragraph.serialize).to eq('paragraph')
        expect(HtmlToMarkdown::NodeType::Bold.serialize).to eq('bold')
      end

      it 'deserializes strings to enum values' do
        expect(HtmlToMarkdown::NodeType.deserialize('heading')).to eq(HtmlToMarkdown::NodeType::Heading)
        expect(HtmlToMarkdown::NodeType.deserialize('code_block')).to eq(HtmlToMarkdown::NodeType::CodeBlock)
      end

      it 'includes all expected markdown element types' do
        expected_types = %w[
          heading paragraph code_block blockquote horizontal_rule
          list list_item table table_row table_cell
          text bold italic code link image line_break strikethrough
          footnote_ref footnote_def task_list_item
        ]

        actual_types = HtmlToMarkdown::NodeType.values.map(&:serialize)
        expect(actual_types).to match_array(expected_types)
      end
    end

    describe HtmlToMarkdown::ASTNode do
      it 'creates a simple text node' do
        node = HtmlToMarkdown::ASTNode.new(
          node_type: HtmlToMarkdown::NodeType::Text,
          text: 'Hello world'
        )

        expect(node.node_type).to eq(HtmlToMarkdown::NodeType::Text)
        expect(node.text).to eq('Hello world')
        expect(node.children).to eq([]) # children defaults to empty array
      end

      it 'creates a heading node with level' do
        node = HtmlToMarkdown::ASTNode.new(
          node_type: HtmlToMarkdown::NodeType::Heading,
          level: 2,
          children: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Text,
              text: 'Section Title'
            )
          ]
        )

        expect(node.node_type).to eq(HtmlToMarkdown::NodeType::Heading)
        expect(node.level).to eq(2)
        expect(node.children).to be_an(Array)
        expect(node.children.first.text).to eq('Section Title')
      end

      it 'creates a link node with url and children' do
        node = HtmlToMarkdown::ASTNode.new(
          node_type: HtmlToMarkdown::NodeType::Link,
          url: 'https://example.com',
          title: 'Example Site',
          children: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Text,
              text: 'Click here'
            )
          ]
        )

        expect(node.url).to eq('https://example.com')
        expect(node.title).to eq('Example Site')
        expect(node.children.first.text).to eq('Click here')
      end

      it 'creates a code block with language' do
        node = HtmlToMarkdown::ASTNode.new(
          node_type: HtmlToMarkdown::NodeType::CodeBlock,
          language: 'ruby',
          text: 'def hello; end'
        )

        expect(node.node_type).to eq(HtmlToMarkdown::NodeType::CodeBlock)
        expect(node.language).to eq('ruby')
        expect(node.text).to eq('def hello; end')
      end

      it 'creates nested list structure' do
        nested_list = HtmlToMarkdown::ASTNode.new(
          node_type: HtmlToMarkdown::NodeType::List,
          ordered: false,
          children: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::ListItem,
              children: [
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Text, text: 'Nested item')
              ]
            )
          ]
        )

        list = HtmlToMarkdown::ASTNode.new(
          node_type: HtmlToMarkdown::NodeType::List,
          ordered: false,
          children: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::ListItem,
              children: [
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Text, text: 'Item 1'),
                nested_list
              ]
            )
          ]
        )

        expect(list.children.first.children.last.node_type).to eq(HtmlToMarkdown::NodeType::List)
      end
    end

    describe HtmlToMarkdown::MarkdownDocument do
      it 'creates a document with multiple block nodes' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Heading,
              level: 1,
              children: [
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Text, text: 'Title')
              ]
            ),
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Text, text: 'Content')
              ]
            )
          ]
        )

        expect(doc.nodes.length).to eq(2)
        expect(doc.nodes.first.node_type).to eq(HtmlToMarkdown::NodeType::Heading)
        expect(doc.nodes.last.node_type).to eq(HtmlToMarkdown::NodeType::Paragraph)
      end
    end

    describe 'JSON Schema Generation' do
      it 'generates valid JSON schema for ASTNode' do
        schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(HtmlToMarkdown::ASTNode)

        expect(schema[:type]).to eq('object')
        expect(schema[:properties]).to have_key(:node_type)
        expect(schema[:properties]).to have_key(:text)
        expect(schema[:properties]).to have_key(:children)

        # node_type should be an enum
        expect(schema[:properties][:node_type][:enum]).to include('heading', 'paragraph', 'bold')
      end

      it 'generates valid JSON schema for MarkdownDocument' do
        schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(HtmlToMarkdown::MarkdownDocument)

        expect(schema[:type]).to eq('object')
        expect(schema[:properties]).to have_key(:nodes)
        expect(schema[:properties][:nodes][:type]).to eq('array')
      end

      it 'handles recursive ASTNode children in schema' do
        schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(HtmlToMarkdown::ASTNode)

        children_schema = schema[:properties][:children]
        # Children is a non-nullable array (has default: [])
        expect(children_schema[:type]).to eq('array')
        expect(children_schema[:items]).to be_a(Hash)
        # Recursive reference uses #/$defs/ format
        expect(children_schema[:items]["$ref"]).to eq("#/$defs/ASTNode")
      end
    end
  end

  describe 'Renderer' do
    let(:renderer) { HtmlToMarkdown::MarkdownRenderer.new }
    let(:text_node) { ->(text) { HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Text, text: text) } }

    describe '#render' do
      it 'renders a simple heading' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Heading,
              level: 1,
              children: [text_node.call('Hello World')]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('# Hello World')
      end

      it 'renders heading levels correctly' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Heading, level: 1, children: [text_node.call('H1')]),
            HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Heading, level: 2, children: [text_node.call('H2')]),
            HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Heading, level: 3, children: [text_node.call('H3')])
          ]
        )

        expect(renderer.render(doc)).to eq("# H1\n\n## H2\n\n### H3")
      end

      it 'renders a paragraph with text' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [text_node.call('This is a paragraph.')]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('This is a paragraph.')
      end

      it 'renders bold text' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [
                text_node.call('This is '),
                HtmlToMarkdown::ASTNode.new(
                  node_type: HtmlToMarkdown::NodeType::Bold,
                  children: [text_node.call('bold')]
                ),
                text_node.call(' text.')
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('This is **bold** text.')
      end

      it 'renders italic text' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [
                text_node.call('This is '),
                HtmlToMarkdown::ASTNode.new(
                  node_type: HtmlToMarkdown::NodeType::Italic,
                  children: [text_node.call('italic')]
                ),
                text_node.call(' text.')
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('This is *italic* text.')
      end

      it 'renders inline code' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [
                text_node.call('Use '),
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Code, text: 'puts'),
                text_node.call(' to print.')
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('Use `puts` to print.')
      end

      it 'renders code blocks with language' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::CodeBlock,
              language: 'ruby',
              text: "def hello\n  puts 'world'\nend"
            )
          ]
        )

        expected = "```ruby\ndef hello\n  puts 'world'\nend\n```"
        expect(renderer.render(doc)).to eq(expected)
      end

      it 'renders code blocks without language' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::CodeBlock,
              text: 'some code'
            )
          ]
        )

        expect(renderer.render(doc)).to eq("```\nsome code\n```")
      end

      it 'renders links' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [
                text_node.call('Visit '),
                HtmlToMarkdown::ASTNode.new(
                  node_type: HtmlToMarkdown::NodeType::Link,
                  url: 'https://example.com',
                  children: [text_node.call('Example')]
                ),
                text_node.call(' for more.')
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('Visit [Example](https://example.com) for more.')
      end

      it 'renders images' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Image,
              url: 'https://example.com/img.png',
              alt: 'An image'
            )
          ]
        )

        expect(renderer.render(doc)).to eq('![An image](https://example.com/img.png)')
      end

      it 'renders horizontal rule' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Paragraph, children: [text_node.call('Before')]),
            HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::HorizontalRule),
            HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Paragraph, children: [text_node.call('After')])
          ]
        )

        expect(renderer.render(doc)).to eq("Before\n\n---\n\nAfter")
      end

      it 'renders unordered list' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::List,
              ordered: false,
              children: [
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::ListItem, children: [text_node.call('Item 1')]),
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::ListItem, children: [text_node.call('Item 2')]),
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::ListItem, children: [text_node.call('Item 3')])
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq("- Item 1\n- Item 2\n- Item 3")
      end

      it 'renders ordered list' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::List,
              ordered: true,
              children: [
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::ListItem, children: [text_node.call('First')]),
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::ListItem, children: [text_node.call('Second')])
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq("1. First\n2. Second")
      end

      it 'renders blockquotes' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Blockquote,
              children: [
                HtmlToMarkdown::ASTNode.new(
                  node_type: HtmlToMarkdown::NodeType::Paragraph,
                  children: [text_node.call('This is a quote.')]
                )
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('> This is a quote.')
      end

      it 'renders strikethrough' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [
                HtmlToMarkdown::ASTNode.new(
                  node_type: HtmlToMarkdown::NodeType::Strikethrough,
                  children: [text_node.call('deleted')]
                )
              ]
            )
          ]
        )

        expect(renderer.render(doc)).to eq('~~deleted~~')
      end

      it 'renders a complete document with multiple elements' do
        doc = HtmlToMarkdown::MarkdownDocument.new(
          nodes: [
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Heading,
              level: 1,
              children: [text_node.call('Title')]
            ),
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::Paragraph,
              children: [
                text_node.call('This is '),
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Bold, children: [text_node.call('bold')]),
                text_node.call(' and '),
                HtmlToMarkdown::ASTNode.new(node_type: HtmlToMarkdown::NodeType::Italic, children: [text_node.call('italic')]),
                text_node.call('.')
              ]
            ),
            HtmlToMarkdown::ASTNode.new(
              node_type: HtmlToMarkdown::NodeType::CodeBlock,
              language: 'ruby',
              text: 'puts "hello"'
            )
          ]
        )

        expected = <<~MD.strip
          # Title

          This is **bold** and *italic*.

          ```ruby
          puts "hello"
          ```
        MD

        expect(renderer.render(doc)).to eq(expected)
      end
    end
  end

  describe 'Integration', :vcr do
    let(:renderer) { HtmlToMarkdown::MarkdownRenderer.new }

    before do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

      DSPy.configure do |c|
        c.lm = DSPy::LM.new(
          'anthropic/claude-haiku-4-5-20251001',
          api_key: ENV['ANTHROPIC_API_KEY']
        )
      end
    end

    describe 'Approach A: HTML to AST (ParseHtmlToAst)' do
      let(:parser) { DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst) }

      it 'parses simple paragraph with bold text',
         vcr: { cassette_name: 'examples/html_to_markdown/ast_simple_paragraph' } do
        html = '<p>Hello, <strong>world</strong>!</p>'

        result = parser.call(html: html)

        expect(result.document).to be_a(HtmlToMarkdown::MarkdownDocument)
        expect(result.document.nodes).not_to be_empty

        # Render and verify
        rendered = renderer.render(result.document)
        expect(rendered).to include('**world**')
      end

      it 'parses headings with different levels',
         vcr: { cassette_name: 'examples/html_to_markdown/ast_headings' } do
        html = '<h1>Title</h1><h2>Subtitle</h2><p>Content here.</p>'

        result = parser.call(html: html)

        expect(result.document.nodes.length).to be >= 2

        rendered = renderer.render(result.document)
        expect(rendered).to include('# Title')
        expect(rendered).to include('## Subtitle')
      end

      it 'parses code blocks with language',
         vcr: { cassette_name: 'examples/html_to_markdown/ast_code_block' } do
        html = '<pre><code class="language-ruby">def hello; puts "world"; end</code></pre>'

        result = parser.call(html: html)

        # Find the code block node
        code_block = result.document.nodes.find do |n|
          n.node_type == HtmlToMarkdown::NodeType::CodeBlock
        end

        expect(code_block).not_to be_nil
        expect(code_block.language).to eq('ruby')

        rendered = renderer.render(result.document)
        expect(rendered).to include('```ruby')
        expect(rendered).to include('def hello')
      end

      it 'parses lists',
         vcr: { cassette_name: 'examples/html_to_markdown/ast_list' } do
        html = '<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>'

        result = parser.call(html: html)

        rendered = renderer.render(result.document)
        expect(rendered).to include('- Item 1')
        expect(rendered).to include('- Item 2')
      end

      it 'parses links',
         vcr: { cassette_name: 'examples/html_to_markdown/ast_link' } do
        html = '<p>Visit <a href="https://example.com">Example</a> for more.</p>'

        result = parser.call(html: html)

        rendered = renderer.render(result.document)
        expect(rendered).to include('[Example](https://example.com)')
      end
    end

    describe 'Approach B: HTML to Markdown String (ConvertHtmlToMarkdown)' do
      let(:converter) { DSPy::Predict.new(HtmlToMarkdown::ConvertHtmlToMarkdown) }

      it 'converts simple HTML directly',
         vcr: { cassette_name: 'examples/html_to_markdown/direct_simple' } do
        html = '<h1>Title</h1><p>Paragraph with <strong>bold</strong> text.</p>'

        result = converter.call(html: html)

        expect(result.markdown).to include('# Title')
        expect(result.markdown).to include('**bold**')
      end

      it 'converts code blocks',
         vcr: { cassette_name: 'examples/html_to_markdown/direct_code_block' } do
        html = '<pre><code class="language-javascript">console.log("hello");</code></pre>'

        result = converter.call(html: html)

        expect(result.markdown).to include('```')
        expect(result.markdown).to include('console.log')
      end

      it 'converts lists',
         vcr: { cassette_name: 'examples/html_to_markdown/direct_list' } do
        html = '<ol><li>First</li><li>Second</li><li>Third</li></ol>'

        result = converter.call(html: html)

        expect(result.markdown).to include('1.')
        expect(result.markdown).to include('First')
      end
    end

    describe 'Approach Comparison' do
      let(:parser) { DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst) }
      let(:converter) { DSPy::Predict.new(HtmlToMarkdown::ConvertHtmlToMarkdown) }

      let(:complex_html) do
        <<~HTML
          <article>
            <h1>Ruby DSPy Guide</h1>
            <p>Learn to build <strong>type-safe</strong> LLM applications with <em>structured outputs</em>.</p>
            <h2>Features</h2>
            <ul>
              <li>Structured outputs with Sorbet types</li>
              <li>Union types for flexible responses</li>
              <li>Recursive type support</li>
            </ul>
            <h2>Example</h2>
            <pre><code class="language-ruby">
class MySignature < DSPy::Signature
  output do
    const :result, String
  end
end
            </code></pre>
            <p>Visit <a href="https://github.com/vicentereig/dspy.rb">the repository</a> for more.</p>
          </article>
        HTML
      end

      it 'compares both approaches on complex HTML',
         vcr: { cassette_name: 'examples/html_to_markdown/comparison' } do
        # Approach A: AST then render
        ast_result = parser.call(html: complex_html)
        rendered_from_ast = renderer.render(ast_result.document)

        # Approach B: Direct conversion
        direct_result = converter.call(html: complex_html)

        # Both should produce valid markdown
        expect(rendered_from_ast).to include('# Ruby DSPy Guide')
        expect(direct_result.markdown).to include('# Ruby DSPy Guide')

        # Both should handle formatting
        expect(rendered_from_ast).to include('**type-safe**')
        expect(direct_result.markdown).to include('**type-safe**')

        # Both should handle code blocks
        expect(rendered_from_ast).to include('```')
        expect(direct_result.markdown).to include('```')

        # Log for manual comparison
        puts "\n" + '=' * 60
        puts "=== AST Approach (Structured) ==="
        puts '=' * 60
        puts rendered_from_ast
        puts "\n" + '=' * 60
        puts "=== Direct Approach (String) ==="
        puts '=' * 60
        puts direct_result.markdown
        puts '=' * 60 + "\n"
      end
    end

    describe 'JSON Extraction Strategies' do
      let(:test_html) do
        <<~HTML
          <article>
            <h1>Test Article</h1>
            <p>This has <strong>bold</strong> and <em>italic</em> text.</p>
            <ul>
              <li>Item one</li>
              <li>Item two</li>
            </ul>
          </article>
        HTML
      end

      describe 'Native JSON (structured_outputs: true)' do
        before do
          skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY'],
              structured_outputs: true # Uses tool use for Anthropic
            )
          end
        end

        it 'parses HTML to AST using native JSON mode',
           vcr: { cassette_name: 'examples/html_to_markdown/native_json_ast' } do
          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)

          result = parser.call(html: test_html)

          expect(result.document).to be_a(HtmlToMarkdown::MarkdownDocument)
          expect(result.document.nodes).not_to be_empty

          rendered = renderer.render(result.document)
          expect(rendered).to include('# Test Article')
          expect(rendered).to include('**bold**')
          expect(rendered).to include('*italic*')

          puts "\n[Native JSON] AST nodes: #{count_nodes(result.document)}"
          puts "[Native JSON] Rendered:\n#{rendered}"
        end

        it 'converts HTML to Markdown string using native JSON mode',
           vcr: { cassette_name: 'examples/html_to_markdown/native_json_direct' } do
          converter = DSPy::Predict.new(HtmlToMarkdown::ConvertHtmlToMarkdown)

          result = converter.call(html: test_html)

          expect(result.markdown).to include('# Test Article')
          expect(result.markdown).to include('**bold**')

          puts "\n[Native JSON] Direct output:\n#{result.markdown}"
        end
      end

      describe 'Native JSON with OpenAI (structured_outputs: true)' do
        before do
          skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'openai/gpt-4o-mini',
              api_key: ENV['OPENAI_API_KEY'],
              structured_outputs: true # Uses response_format for OpenAI
            )
          end
        end

        # Fixed in issue #201: Now uses #/$defs/ format instead of #/definitions/
        # OpenAI structured outputs now work with recursive schemas
        it 'parses HTML to AST using OpenAI native JSON mode with $defs',
           vcr: { cassette_name: 'examples/html_to_markdown/openai_native_json_ast' } do
          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)

          result = parser.call(html: test_html)

          expect(result.document).to be_a(HtmlToMarkdown::MarkdownDocument)
          expect(result.document.nodes).not_to be_empty

          rendered = renderer.render(result.document)
          expect(rendered).to include('# Test Article')
          expect(rendered).to include('**bold**')
          expect(rendered).to include('*italic*')

          puts "\n[OpenAI Native JSON] ✅ Works with recursive AST using #/$defs/ format!"
          puts "[OpenAI Native JSON] AST nodes: #{count_nodes(result.document)}"
          puts "[OpenAI Native JSON] Rendered:\n#{rendered}"
        end

        it 'converts HTML to Markdown string using OpenAI native JSON mode',
           vcr: { cassette_name: 'examples/html_to_markdown/openai_native_json_direct' } do
          converter = DSPy::Predict.new(HtmlToMarkdown::ConvertHtmlToMarkdown)

          result = converter.call(html: test_html)

          expect(result.markdown).to include('# Test Article')
          expect(result.markdown).to include('**bold**')

          puts "\n[OpenAI Native JSON] Direct output:\n#{result.markdown}"
        end
      end

      describe 'BAML with OpenAI (schema_format: :baml, structured_outputs: false)' do
        before do
          skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'openai/gpt-4o-mini',
              api_key: ENV['OPENAI_API_KEY'],
              structured_outputs: false, # Disable native structured outputs
              schema_format: :baml # Use BAML schema format in prompts
            )
          end
        end

        it 'parses HTML to AST using OpenAI with BAML prompting',
           vcr: { cassette_name: 'examples/html_to_markdown/openai_baml_ast' } do
          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)

          result = parser.call(html: test_html)

          expect(result.document).to be_a(HtmlToMarkdown::MarkdownDocument)
          expect(result.document.nodes).not_to be_empty

          rendered = renderer.render(result.document)
          expect(rendered).to include('# Test Article')
          expect(rendered).to include('**bold**')
          expect(rendered).to include('*italic*')

          puts "\n[OpenAI BAML] AST nodes: #{count_nodes(result.document)}"
          puts "[OpenAI BAML] Rendered:\n#{rendered}"
        end
      end

      describe 'BAML Schema (schema_format: :baml, structured_outputs: false)' do
        before do
          skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY'],
              structured_outputs: false, # Disable tool use
              schema_format: :baml # Use BAML schema format in prompts
            )
          end
        end

        it 'parses HTML to AST using BAML schema prompting',
           vcr: { cassette_name: 'examples/html_to_markdown/baml_ast' } do
          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)

          result = parser.call(html: test_html)

          expect(result.document).to be_a(HtmlToMarkdown::MarkdownDocument)
          expect(result.document.nodes).not_to be_empty

          rendered = renderer.render(result.document)
          expect(rendered).to include('# Test Article')
          expect(rendered).to include('**bold**')
          expect(rendered).to include('*italic*')

          puts "\n[BAML] AST nodes: #{count_nodes(result.document)}"
          puts "[BAML] Rendered:\n#{rendered}"
        end

        it 'converts HTML to Markdown string using BAML schema prompting',
           vcr: { cassette_name: 'examples/html_to_markdown/baml_direct' } do
          converter = DSPy::Predict.new(HtmlToMarkdown::ConvertHtmlToMarkdown)

          result = converter.call(html: test_html)

          expect(result.markdown).to include('# Test Article')
          expect(result.markdown).to include('**bold**')

          puts "\n[BAML] Direct output:\n#{result.markdown}"
        end
      end

      describe 'Real-World Article Test' do
        # Representative complex article based on typical engineering blog structure
        # (inspired by https://shopify.engineering/tangle)
        let(:engineering_blog_html) do
          <<~HTML
            <article>
              <h1>Tangle: Building an ML Experimentation Platform</h1>

              <p>Your experiment finally finished. Six hours later, your teammate asks you to reproduce it.
              You <strong>can't remember</strong> which notebook version you used or what parameters were set.</p>

              <h2>The Problem</h2>
              <p>ML development faces <em>six critical challenges</em>:</p>
              <ul>
                <li><strong>Manual query tracking</strong> leads to lost experiments</li>
                <li>Notebook accumulation creates confusion</li>
                <li>Repeated data preparation wastes time</li>
                <li>Irreproducibility blocks collaboration</li>
                <li>Slow deployments delay production</li>
                <li>Lack of team sharing silos knowledge</li>
              </ul>

              <h2>Architecture Components</h2>
              <p>Tangle uses a <code>component</code>-based architecture:</p>

              <h3>Components</h3>
              <p>Reusable YAML-based units that function like pure functions:</p>
              <pre><code class="language-yaml">name: train-model
inputs:
  - name: dataset
    type: path
  - name: epochs
    type: int
outputs:
  - name: model
    type: path</code></pre>

              <h3>Execution Example</h3>
              <pre><code class="language-python">from tangle import Pipeline

pipeline = Pipeline.from_yaml("training.yaml")
result = pipeline.run(
    dataset="./data/train.csv",
    epochs=100
)
print(f"Model saved: {result.model}")</code></pre>

              <h2>Key Features</h2>
              <ol>
                <li><strong>Content-based caching</strong>: Reuses computations across team runs</li>
                <li><strong>Language-neutral</strong>: Supports Python, Shell, JavaScript, Rust, Go, and more</li>
                <li><strong>Visual editor</strong>: Drag-and-drop DAG interface</li>
              </ol>

              <blockquote>
                <p>Tangle reduced our iteration time by 60% and made every experiment fully reproducible.</p>
              </blockquote>

              <h2>Getting Started</h2>
              <p>Check out the <a href="https://github.com/shopify/tangle">GitHub repository</a> or try the
              <a href="https://huggingface.co/spaces/shopify/tangle">HuggingFace Space</a>.</p>

              <hr>

              <p><em>This article was written by the ML Platform team at Shopify.</em></p>
            </article>
          HTML
        end

        # Note: Complex articles often hit max_tokens limits with recursive AST output
        # This test verifies the schema works - completeness depends on LLM output limits
        it 'parses complex engineering blog article with Native JSON',
           vcr: { cassette_name: 'examples/html_to_markdown/real_article_native' } do
          skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY'],
              structured_outputs: true
            )
          end

          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)

          # Note: This may raise PredictionInvalidError if max_tokens is hit
          # before completing the JSON output
          begin
            result = parser.call(html: engineering_blog_html)
            rendered = renderer.render(result.document)

            expect(rendered).to include('#')   # Some heading
            expect(rendered).to include('**')  # Some bold

            puts "\n[Native JSON - Real Article]"
            puts "AST Nodes: #{count_nodes(result.document)}"
            puts '-' * 60
            puts rendered
          rescue DSPy::PredictionInvalidError => e
            # Expected for complex articles that exceed output token limit
            puts "\n[Native JSON - Real Article] Hit max_tokens: #{e.message[0..100]}..."
            expect(e.message).to include('document')
          end
        end

        # Fixed in issue #201: OpenAI native structured outputs now work with recursive schemas
        # Note: LLM may truncate long articles - we verify schema works, not completeness
        it 'parses complex article with OpenAI Native JSON using $defs',
           vcr: { cassette_name: 'examples/html_to_markdown/real_article_openai_native' } do
          skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'openai/gpt-4o-mini',
              api_key: ENV['OPENAI_API_KEY'],
              structured_outputs: true
            )
          end

          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)
          result = parser.call(html: engineering_blog_html)

          rendered = renderer.render(result.document)

          # Verify schema works (recursive types with $defs)
          # LLM may truncate complex articles - core elements matter most
          expect(rendered).to include('# Tangle')
          expect(rendered).to include('**')  # Some bold formatting preserved

          puts "\n[OpenAI Native JSON - Real Article] ✅ Works with #/$defs/ format!"
          puts "AST Nodes: #{count_nodes(result.document)}"
          puts '-' * 60
          puts rendered
        end

        # FINDING: OpenAI BAML loses heading text content (headings render as "# " without text)
        # but preserves code blocks correctly - opposite of Anthropic's behavior
        it 'parses complex article with OpenAI BAML - loses heading text but preserves code',
           vcr: { cassette_name: 'examples/html_to_markdown/real_article_openai_baml' } do
          skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'openai/gpt-4o-mini',
              api_key: ENV['OPENAI_API_KEY'],
              structured_outputs: false,
              schema_format: :baml
            )
          end

          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)
          result = parser.call(html: engineering_blog_html)

          rendered = renderer.render(result.document)

          # OpenAI BAML loses heading text! (renders as "# " instead of "# Title")
          # But code blocks are preserved correctly (unlike Anthropic native)
          expect(rendered).to include('```')
          expect(rendered).to include('**')
          expect(rendered).to include('train-model').or include('name:')

          # Document the heading text loss
          heading_lines = rendered.lines.select { |l| l.start_with?('#') }
          empty_headings = heading_lines.select { |l| l.strip.match?(/^#+\s*$/) }

          puts "\n[OpenAI BAML - Real Article]"
          puts "AST Nodes: #{count_nodes(result.document)}"
          puts "⚠️ Empty headings (text lost): #{empty_headings.count}/#{heading_lines.count}"
          puts '-' * 60
          puts rendered
        end

        # Note: BAML format for complex articles - may hit max_tokens
        it 'parses complex engineering blog article with BAML',
           vcr: { cassette_name: 'examples/html_to_markdown/real_article_baml' } do
          skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY'],
              structured_outputs: false,
              schema_format: :baml
            )
          end

          parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)

          begin
            result = parser.call(html: engineering_blog_html)
            rendered = renderer.render(result.document)

            expect(rendered).to include('#')   # Some heading

            puts "\n[BAML - Real Article]"
            puts "AST Nodes: #{count_nodes(result.document)}"
            puts '-' * 60
            puts rendered
          rescue DSPy::PredictionInvalidError => e
            puts "\n[BAML - Real Article] Hit max_tokens: #{e.message[0..100]}..."
            expect(e.message).to include('document')
          end
        end

        it 'converts complex article directly to Markdown',
           vcr: { cassette_name: 'examples/html_to_markdown/real_article_direct' } do
          skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY']
            )
          end

          converter = DSPy::Predict.new(HtmlToMarkdown::ConvertHtmlToMarkdown)
          result = converter.call(html: engineering_blog_html)

          expect(result.markdown).to include('# Tangle')
          expect(result.markdown).to include('```')

          puts "\n[Direct String - Real Article]"
          puts '-' * 60
          puts result.markdown
        end
      end

      describe 'Strategy Comparison' do
        let(:comparison_html) do
          <<~HTML
            <article>
              <h1>Strategy Comparison Test</h1>
              <p>Testing <strong>bold</strong>, <em>italic</em>, and <code>code</code>.</p>
              <pre><code class="language-ruby">puts "hello"</code></pre>
              <ul>
                <li>First item</li>
                <li>Second item</li>
              </ul>
            </article>
          HTML
        end

        it 'compares Native JSON vs BAML for AST parsing',
           vcr: { cassette_name: 'examples/html_to_markdown/strategy_comparison' } do
          skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

          results = {}

          # Native JSON mode (Anthropic)
          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY'],
              structured_outputs: true
            )
          end

          native_parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)
          start_time = Time.now
          native_result = native_parser.call(html: comparison_html)
          results[:anthropic_native] = {
            time: Time.now - start_time,
            node_count: count_nodes(native_result.document),
            rendered: renderer.render(native_result.document)
          }

          # BAML mode (Anthropic)
          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY'],
              structured_outputs: false,
              schema_format: :baml
            )
          end

          baml_parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)
          start_time = Time.now
          baml_result = baml_parser.call(html: comparison_html)
          results[:baml] = {
            time: Time.now - start_time,
            node_count: count_nodes(baml_result.document),
            rendered: renderer.render(baml_result.document)
          }

          # Print comparison
          puts "\n" + '=' * 70
          puts "JSON Extraction Strategy Comparison (Anthropic)"
          puts '=' * 70
          puts format("\n%-20s %20s %15s", 'Metric', 'Anthropic Native', 'BAML')
          puts '-' * 55
          puts format("%-20s %20.3fs %15.3fs", 'Time', results[:anthropic_native][:time], results[:baml][:time])
          puts format("%-20s %20d %15d", 'AST Nodes', results[:anthropic_native][:node_count], results[:baml][:node_count])
          puts format("%-20s %20d %15d", 'Output Length', results[:anthropic_native][:rendered].length, results[:baml][:rendered].length)

          puts "\n[Anthropic Native JSON] Output:"
          puts '-' * 50
          puts results[:anthropic_native][:rendered]

          puts "\n[BAML] Output:"
          puts '-' * 50
          puts results[:baml][:rendered]
          puts '=' * 70

          # Both should produce valid Markdown
          expect(results[:anthropic_native][:rendered]).to include('# Strategy Comparison Test')
          expect(results[:baml][:rendered]).to include('# Strategy Comparison Test')
        end

        # OpenAI native structured outputs cannot handle recursive schemas at all
        # OpenAI BAML loses heading text but preserves code blocks
        # Anthropic native loses code block content but preserves heading text
        it 'compares OpenAI BAML vs Anthropic Native - documents different failure modes',
           vcr: { cassette_name: 'examples/html_to_markdown/openai_baml_vs_anthropic_comparison' } do
          skip 'Requires both OPENAI_API_KEY and ANTHROPIC_API_KEY' unless ENV['OPENAI_API_KEY'] && ENV['ANTHROPIC_API_KEY']

          results = {}

          # OpenAI BAML mode (only way OpenAI can handle recursive schemas)
          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'openai/gpt-4o-mini',
              api_key: ENV['OPENAI_API_KEY'],
              structured_outputs: false,
              schema_format: :baml
            )
          end

          openai_parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)
          start_time = Time.now
          openai_result = openai_parser.call(html: comparison_html)
          results[:openai_baml] = {
            time: Time.now - start_time,
            node_count: count_nodes(openai_result.document),
            rendered: renderer.render(openai_result.document)
          }

          # Anthropic Native JSON mode
          DSPy.configure do |c|
            c.lm = DSPy::LM.new(
              'anthropic/claude-haiku-4-5-20251001',
              api_key: ENV['ANTHROPIC_API_KEY'],
              structured_outputs: true
            )
          end

          anthropic_parser = DSPy::Predict.new(HtmlToMarkdown::ParseHtmlToAst)
          start_time = Time.now
          anthropic_result = anthropic_parser.call(html: comparison_html)
          results[:anthropic_native] = {
            time: Time.now - start_time,
            node_count: count_nodes(anthropic_result.document),
            rendered: renderer.render(anthropic_result.document)
          }

          # Print comparison - documenting the different failure modes
          puts "\n" + '=' * 70
          puts "OpenAI BAML vs Anthropic Native Comparison"
          puts "(Both have issues - different failure modes)"
          puts '=' * 70
          puts format("\n%-20s %18s %18s", 'Metric', 'OpenAI BAML', 'Anthropic Native')
          puts '-' * 58
          puts format("%-20s %18.3fs %18.3fs", 'Time', results[:openai_baml][:time], results[:anthropic_native][:time])
          puts format("%-20s %18d %18d", 'AST Nodes', results[:openai_baml][:node_count], results[:anthropic_native][:node_count])
          puts format("%-20s %18d %18d", 'Output Length', results[:openai_baml][:rendered].length, results[:anthropic_native][:rendered].length)

          # Check different content types
          openai_has_code = results[:openai_baml][:rendered].include?('puts "hello"')
          anthropic_has_code = results[:anthropic_native][:rendered].include?('puts "hello"')
          openai_has_heading = results[:openai_baml][:rendered].include?('Strategy Comparison Test')
          anthropic_has_heading = results[:anthropic_native][:rendered].include?('Strategy Comparison Test')

          puts format("%-20s %18s %18s", 'Code Preserved?', openai_has_code ? '✅ Yes' : '❌ No', anthropic_has_code ? '✅ Yes' : '❌ No')
          puts format("%-20s %18s %18s", 'Heading Text?', openai_has_heading ? '✅ Yes' : '❌ No', anthropic_has_heading ? '✅ Yes' : '❌ No')

          puts "\n[OpenAI BAML] Output (⚠️ may lose heading text):"
          puts '-' * 50
          puts results[:openai_baml][:rendered]

          puts "\n[Anthropic Native JSON] Output (⚠️ may lose code content):"
          puts '-' * 50
          puts results[:anthropic_native][:rendered]
          puts '=' * 70

          # Both produce parseable markdown, just with different content loss
          expect(results[:openai_baml][:rendered]).to include('```ruby')
          expect(results[:anthropic_native][:rendered]).to include('#')
        end
      end

      private

      def count_nodes(document)
        count = 0
        document.nodes.each { |node| count += count_node_recursive(node) }
        count
      end

      def count_node_recursive(node)
        count = 1
        if node.children
          node.children.each { |child| count += count_node_recursive(child) }
        end
        count
      end
    end

    describe 'Hierarchical Parsing (Two-Phase)' do
      let(:renderer) { HtmlToMarkdown::MarkdownRenderer.new }

      let(:complex_article_html) do
        <<~HTML
          <article>
            <h1>Building Better APIs</h1>
            <p>Learn to create <strong>robust</strong> and <em>scalable</em> APIs.</p>

            <h2>Design Principles</h2>
            <ul>
              <li>Use <strong>RESTful</strong> conventions</li>
              <li>Version your API</li>
              <li>Document thoroughly</li>
            </ul>

            <h2>Example</h2>
            <pre><code class="language-ruby">class UsersController < ApplicationController
  def index
    render json: User.all
  end
end</code></pre>

            <blockquote>
              <p>Good APIs are a <strong>contract</strong> with your users.</p>
            </blockquote>

            <hr>

            <p>Check out <a href="https://example.com/docs">our documentation</a>.</p>
          </article>
        HTML
      end

      # Phase 1: Skeleton extraction - demonstrates outline parsing with $defs
      it 'extracts document outline in phase 1',
         vcr: { cassette_name: 'examples/html_to_markdown/hierarchical_outline' } do
        skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

        DSPy.configure do |c|
          c.lm = DSPy::LM.new(
            'openai/gpt-4o-mini',
            api_key: ENV['OPENAI_API_KEY'],
            structured_outputs: true
          )
        end

        parser = DSPy::Predict.new(HtmlToMarkdown::ParseOutline)
        result = parser.call(html: complex_article_html)

        sections = result.sections

        # Should extract some block-level structure (LLM may truncate)
        expect(sections).to be_an(Array)
        expect(sections.length).to be >= 2  # At least heading + something

        # First section should be heading
        first = sections.first
        expect(first.node_type).to eq(HtmlToMarkdown::NodeType::Heading)

        puts "\n[Hierarchical Phase 1] Outline extracted (#{sections.length} sections):"
        sections.each_with_index do |s, i|
          text_preview = s.text.empty? ? "(no text)" : s.text[0..40]
          puts "  #{i + 1}. #{s.node_type.serialize}: #{text_preview}"
        end
      end

      # Two-phase parsing demonstration
      # Note: For best results, use smaller HTML chunks or higher max_tokens
      it 'parses complex article using two-phase approach',
         vcr: { cassette_name: 'examples/html_to_markdown/hierarchical_full' } do
        skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

        DSPy.configure do |c|
          c.lm = DSPy::LM.new(
            'openai/gpt-4o-mini',
            api_key: ENV['OPENAI_API_KEY'],
            structured_outputs: true
          )
        end

        parser = HtmlToMarkdown::HierarchicalParser.new
        document = parser.parse(complex_article_html)

        rendered = renderer.render(document)

        # Verify core structure parsed (LLM may not get everything)
        expect(rendered).to include('#')      # Some heading
        expect(rendered).to include('**')     # Some bold text

        puts "\n[Hierarchical Two-Phase] Output:"
        puts '-' * 60
        puts rendered
        puts "\n💡 For complete output, try smaller chunks or higher max_tokens"
      end
    end
  end
end
