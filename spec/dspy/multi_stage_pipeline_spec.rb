require 'spec_helper'
require_relative 'lib/multi_stage_pipeline'

RSpec.describe DraftArticle do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  it 'drafts the outline about There Is a Liberal Answer to Elon Musk' do
    VCR.use_cassette('openai/gpt4o-mini/draft_outline_liberal_answer_to_elon_musk') do
      outliner = DSPy::ChainOfThought.new(Outline)

      outline = outliner.call(topic: "There Is a Liberal Answer to Elon Musk")
      expect(outline.keys).to eq([:topic, :title, :sections, :section_subheadings, :reasoning])
    end
  end

  it 'drafts a section about There Is a Liberal Answer to Elon Musk' do
    VCR.use_cassette('openai/gpt4o-mini/draft_section_liberal_answer_to_elon_musk') do
      drafter = DSPy::ChainOfThought.new(DraftSection)
      section = drafter.call(
        topic: "There Is a Liberal Answer to Elon Musk",
        section_heading: "Introduction",
        section_subheadings: []
      )

      expect(section.keys).to eq([:topic, :section_heading, :section_subheadings, :content, :reasoning])
    end
  end

  it 'drafts an article about World Cup 2002' do
    VCR.use_cassette('openai/gpt4o-mini/draft_article_worldcup') do
      draft_article = ArticleDrafter.new

      article = draft_article.call("World Cup 2002")
      expect(article).to be_a(DraftArticle)
      expect(article.title).to be_a(String)
    end
  end

  it 'draft sections are hashes' do
    VCR.use_cassette('openai/gpt4o-mini/draft_article_worldcup') do
      drafter = ArticleDrafter.new
      draft_article = drafter.call("World Cup 2002")

      draft_section = draft_article.sections.first
      expect(draft_section.keys).to eq([:topic, :section_heading, :section_subheadings, :content, :reasoning])
    end
  end
end
