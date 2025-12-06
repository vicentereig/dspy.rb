# frozen_string_literal: true

module RubyLLMTestHelpers
  def self.included(base)
    base.class_eval do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }
      let(:mock_context) { instance_double(RubyLLM::Context) }
      let(:mock_message) do
        instance_double(
          RubyLLM::Message,
          content: 'Hello back!',
          model_id: 'gpt-4o',
          input_tokens: 10,
          output_tokens: 5
        )
      end

      let(:mock_model_info) do
        instance_double('RubyLLM::Model::Info', provider: :openai)
      end

      before do
        allow(RubyLLM).to receive(:context).and_yield(double('config').as_null_object).and_return(mock_context)
        allow(mock_context).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_message)

        # Mock the model registry
        mock_models = double('models')
        allow(RubyLLM).to receive(:models).and_return(mock_models)
        allow(mock_models).to receive(:find).and_return(mock_model_info)
      end
    end
  end
end
