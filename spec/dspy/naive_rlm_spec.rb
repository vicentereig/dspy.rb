# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::NaiveRLM do
  describe DSPy::NaiveRLM::Actions do
    describe DSPy::NaiveRLM::Actions::Peek do
      it 'has start_line and end_line fields' do
        peek = DSPy::NaiveRLM::Actions::Peek.new(start_line: 1, end_line: 10)
        expect(peek.start_line).to eq(1)
        expect(peek.end_line).to eq(10)
      end
    end

    describe DSPy::NaiveRLM::Actions::Grep do
      it 'has pattern field' do
        grep = DSPy::NaiveRLM::Actions::Grep.new(pattern: 'foo')
        expect(grep.pattern).to eq('foo')
      end
    end

    describe DSPy::NaiveRLM::Actions::Partition do
      it 'has chunk_size with default' do
        partition = DSPy::NaiveRLM::Actions::Partition.new
        expect(partition.chunk_size).to eq(500)
      end

      it 'allows custom chunk_size' do
        partition = DSPy::NaiveRLM::Actions::Partition.new(chunk_size: 100)
        expect(partition.chunk_size).to eq(100)
      end
    end

    describe DSPy::NaiveRLM::Actions::Finish do
      it 'has answer field' do
        finish = DSPy::NaiveRLM::Actions::Finish.new(answer: 'The answer is 42')
        expect(finish.answer).to eq('The answer is 42')
      end
    end
  end

  describe DSPy::NaiveRLM::Result do
    it 'has required fields with defaults' do
      result = DSPy::NaiveRLM::Result.new(answer: 'test', iterations: 3)
      expect(result.answer).to eq('test')
      expect(result.iterations).to eq(3)
      expect(result.history).to eq([])
      expect(result.max_iterations_reached).to be false
    end

    it 'accepts all fields' do
      result = DSPy::NaiveRLM::Result.new(
        answer: 'answer',
        iterations: 5,
        history: ['action1', 'action2'],
        max_iterations_reached: true
      )
      expect(result.history).to eq(['action1', 'action2'])
      expect(result.max_iterations_reached).to be true
    end
  end

  describe DSPy::NaiveRLM::Relevance do
    it 'defines relevance levels' do
      expect(DSPy::NaiveRLM::Relevance::High.serialize).to eq('high')
      expect(DSPy::NaiveRLM::Relevance::None.serialize).to eq('none')
    end
  end

  describe DSPy::NaiveRLM::Navigator do
    subject(:navigator) { described_class.new(max_iterations: 5) }

    let(:sample_document) do
      [
        'Title: Research Paper on Machine Learning',
        'Author: Jane Smith',
        '',
        'Abstract',
        'This paper explores the application of machine learning',
        'to medical diagnosis with promising results.',
        '',
        'Introduction',
        'Machine learning has revolutionized many fields.',
        'In healthcare, it shows particular promise.',
        '',
        'Methods',
        'We used a dataset of 10,000 patient records.',
        'The model was trained using cross-validation.',
        '',
        'Results',
        'Our model achieved 95% accuracy.',
        'Patient outcomes improved by 23%.',
        'The false positive rate was only 2%.',
        '',
        'Discussion',
        'These results are significant.',
        'Further research is needed.',
        '',
        'Conclusion',
        'Machine learning can improve medical diagnosis.',
        '',
        'References',
        '1. Smith et al. 2020',
        '2. Jones et al. 2021'
      ]
    end

    describe '#initialize' do
      it 'sets max_iterations' do
        expect(navigator.max_iterations).to eq(5)
      end

      it 'uses default max_iterations when not specified' do
        default_navigator = described_class.new
        expect(default_navigator.max_iterations).to eq(10)
      end
    end

    describe '#named_predictors' do
      it 'returns selector and summarizer' do
        predictors = navigator.named_predictors
        expect(predictors.map(&:first)).to contain_exactly('selector', 'summarizer')
      end
    end

    describe 'primitive execution (private methods)' do
      describe '#build_preview' do
        it 'builds numbered preview with truncation indicator' do
          preview = navigator.send(:build_preview, sample_document, 5)

          expect(preview).to include('1: Title: Research Paper')
          expect(preview).to include('5: This paper explores')
          expect(preview).to include('[30 total lines]')
          expect(preview).not_to include('6:')
        end

        it 'handles documents shorter than preview count' do
          short_doc = ['Line 1', 'Line 2']
          preview = navigator.send(:build_preview, short_doc, 100)

          expect(preview).to include('1: Line 1')
          expect(preview).to include('2: Line 2')
          expect(preview).to include('[2 total lines]')
        end
      end

      describe '#execute_peek' do
        it 'extracts line range with line numbers' do
          result = navigator.send(:execute_peek, sample_document, 4, 7)

          expect(result[:text]).to include('4: Abstract')
          expect(result[:text]).to include('5: This paper explores')
          expect(result[:text]).to include('7:')
          expect(result[:context]).to eq('[4-7]')
          expect(result[:start]).to eq(4)
          expect(result[:end]).to eq(7)
        end

        it 'clamps out-of-bounds indices' do
          result = navigator.send(:execute_peek, sample_document, -5, 1000)

          expect(result[:start]).to eq(1)
          expect(result[:end]).to eq(30)
        end

        it 'handles reversed indices by swapping' do
          result = navigator.send(:execute_peek, sample_document, 10, 5)

          expect(result[:start]).to eq(5)
          expect(result[:end]).to eq(10)
        end
      end

      describe '#execute_grep' do
        it 'finds matches with context' do
          matches = navigator.send(:execute_grep, sample_document, 'accuracy')

          expect(matches.length).to eq(1)
          expect(matches.first[:match_line]).to eq(17)
          expect(matches.first[:text]).to include('95% accuracy')
          expect(matches.first[:context]).to include("matched 'accuracy'")
        end

        it 'returns multiple non-overlapping matches' do
          matches = navigator.send(:execute_grep, sample_document, 'machine learning')

          expect(matches.length).to be >= 1
          matches.each do |match|
            expect(match[:text].downcase).to include('machine learning')
          end
        end

        it 'is case insensitive' do
          matches = navigator.send(:execute_grep, sample_document, 'RESULTS')

          expect(matches.length).to be >= 1
        end

        it 'returns empty array for no matches' do
          matches = navigator.send(:execute_grep, sample_document, 'xyznonexistent')

          expect(matches).to eq([])
        end

        it 'returns empty array for invalid regex' do
          matches = navigator.send(:execute_grep, sample_document, '[invalid(regex')

          expect(matches).to eq([])
        end

        it 'returns empty array for empty pattern' do
          matches = navigator.send(:execute_grep, sample_document, '')

          expect(matches).to eq([])
        end

        it 'limits matches to MAX_GREP_MATCHES' do
          # Create document with many matches
          many_matches_doc = 50.times.map { |i| "Line #{i}: keyword here" }
          matches = navigator.send(:execute_grep, many_matches_doc, 'keyword')

          expect(matches.length).to be <= 5
        end

        it 'deduplicates overlapping matches' do
          # Adjacent lines matching should not produce overlapping results
          adjacent_doc = [
            'First line',
            'Match here',
            'Match here again',
            'Match here third',
            'Last line'
          ]
          matches = navigator.send(:execute_grep, adjacent_doc, 'Match')

          # With context of 10 lines, all three matches would overlap
          expect(matches.length).to eq(1)
        end
      end

      describe '#partition_lines' do
        it 'chunks document into specified sizes' do
          chunks = navigator.send(:partition_lines, sample_document, 10)

          expect(chunks.length).to eq(3)
          expect(chunks[0][:context]).to eq('Lines 1-10')
          expect(chunks[1][:context]).to eq('Lines 11-20')
          expect(chunks[2][:context]).to eq('Lines 21-30')
        end

        it 'handles uneven last chunk' do
          chunks = navigator.send(:partition_lines, sample_document, 7)

          last_chunk = chunks.last
          expect(last_chunk[:context]).to eq('Lines 29-30')
        end
      end

      describe '#ranges_overlap?' do
        it 'returns true for overlapping ranges' do
          expect(navigator.send(:ranges_overlap?, 1..10, 5..15)).to be true
          expect(navigator.send(:ranges_overlap?, 5..15, 1..10)).to be true
        end

        it 'returns false for non-overlapping ranges' do
          expect(navigator.send(:ranges_overlap?, 1..5, 10..15)).to be false
        end

        it 'returns true for contained ranges' do
          expect(navigator.send(:ranges_overlap?, 1..20, 5..10)).to be true
        end
      end

      describe '#synthesize_from_history' do
        it 'returns message for empty history' do
          result = navigator.send(:synthesize_from_history, [])
          expect(result).to eq('No information gathered')
        end

        it 'combines last 3 history entries' do
          history = [
            'GREP: Found abstract',
            'PEEK: Read results section',
            'GREP: Found statistics',
            'PEEK: Read conclusion'
          ]
          result = navigator.send(:synthesize_from_history, history)

          expect(result).to include('PEEK: Read results section')
          expect(result).to include('GREP: Found statistics')
          expect(result).to include('PEEK: Read conclusion')
          expect(result).not_to include('Found abstract')
        end
      end
    end

    describe 'signatures' do
      describe DSPy::NaiveRLM::SelectAction do
        it 'has required input fields' do
          input_props = DSPy::NaiveRLM::SelectAction.input_struct_class.props

          expect(input_props).to have_key(:query)
          expect(input_props).to have_key(:document_stats)
          expect(input_props).to have_key(:context_window)
          expect(input_props).to have_key(:history)
        end

        it 'has output fields with T.any action type' do
          output_props = DSPy::NaiveRLM::SelectAction.output_struct_class.props

          expect(output_props).to have_key(:reasoning)
          expect(output_props).to have_key(:action)
          # Action is now a T.any union type, not individual optional fields
          expect(output_props.keys).to contain_exactly(:reasoning, :action)
        end

        it 'has a concise description' do
          expect(DSPy::NaiveRLM::SelectAction.description).to include('navigate a document')
        end
      end

      describe DSPy::NaiveRLM::SummarizeChunk do
        it 'has required input fields' do
          input_props = DSPy::NaiveRLM::SummarizeChunk.input_struct_class.props

          expect(input_props).to have_key(:query)
          expect(input_props).to have_key(:chunk_context)
          expect(input_props).to have_key(:chunk_text)
        end

        it 'has required output fields' do
          output_props = DSPy::NaiveRLM::SummarizeChunk.output_struct_class.props

          expect(output_props).to have_key(:summary)
          expect(output_props).to have_key(:relevance)
        end
      end
    end
  end
end
