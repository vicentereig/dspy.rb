# frozen_string_literal: true

require 'spec_helper'
require 'sorbet/toon'

module PromptToonSpec
  class Source < T::Struct
    prop :name, String
    prop :url, String
  end

  class Signature < DSPy::Signature
    description 'Render inputs/outputs as TOON'

    input do
      const :query, String
      const :limit, Integer, default: 2
    end

    output do
      const :summary, String
      const :sources, T::Array[Source]
    end
  end
end

RSpec.describe DSPy::Prompt, 'TOON data format' do
  let(:signature_class) { PromptToonSpec::Signature }

  subject(:prompt) do
    DSPy::Prompt.from_signature(
      signature_class,
      schema_format: :toon,
      data_format: :toon
    )
  end

  it 'renders system prompt with TOON instructions' do
    system_prompt = prompt.render_system_prompt

    expect(system_prompt).to include('TOON order')
    expect(system_prompt).to include('```toon')
    expect(system_prompt).to include('Tabular columns: name, url')
  end

  it 'renders user prompt with TOON block' do
    user_prompt = prompt.render_user_prompt(
      {
        query: 'latest research',
        limit: 3
      }
    )

    expect(user_prompt).to include('```toon')
    expect(user_prompt).to include('query: latest research')
    expect(user_prompt).to include('limit: 3')
  end
end
