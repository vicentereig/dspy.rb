# frozen_string_literal: true

module DSPy
  class LM
    module VisionModels
      # OpenAI vision-capable models
      OPENAI_VISION_MODELS = [
        'gpt-4-vision-preview',
        'gpt-4-turbo',
        'gpt-4-turbo-2024-04-09',
        'gpt-4-turbo-preview',
        'gpt-4o',
        'gpt-4o-2024-05-13',
        'gpt-4o-2024-08-06',
        'gpt-4o-mini',
        'gpt-4o-mini-2024-07-18'
      ].freeze
      
      # Anthropic vision-capable models
      ANTHROPIC_VISION_MODELS = [
        'claude-3-opus-20240229',
        'claude-3-sonnet-20240229',
        'claude-3-haiku-20240307',
        'claude-3-5-sonnet-20241022',
        'claude-3-5-sonnet-20240620',
        'claude-3-5-haiku-20241022'
      ].freeze
      
      # Gemini vision-capable models (all Gemini models support vision)
      # Based on official Google AI API documentation (March 2025)
      GEMINI_VISION_MODELS = [
        # Gemini 2.5 series (2025)
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
        # Gemini 2.0 series (2024-2025)
        'gemini-2.0-flash',
        'gemini-2.0-flash-lite',
        # Gemini 1.5 series
        'gemini-1.5-pro',
        'gemini-1.5-flash',
        'gemini-1.5-flash-8b'
      ].freeze
      
      def self.supports_vision?(provider, model)
        case provider.to_s.downcase
        when 'openai'
          OPENAI_VISION_MODELS.any? { |m| model.include?(m) }
        when 'anthropic'
          ANTHROPIC_VISION_MODELS.any? { |m| model.include?(m) }
        when 'gemini'
          GEMINI_VISION_MODELS.any? { |m| model.include?(m) }
        else
          false
        end
      end
      
      def self.validate_vision_support!(provider, model)
        unless supports_vision?(provider, model)
          raise ArgumentError, "Model #{model} does not support vision. Vision-capable models for #{provider}: #{vision_models_for(provider).join(', ')}"
        end
      end
      
      def self.vision_models_for(provider)
        case provider.to_s.downcase
        when 'openai'
          OPENAI_VISION_MODELS
        when 'anthropic'
          ANTHROPIC_VISION_MODELS
        when 'gemini'
          GEMINI_VISION_MODELS
        else
          []
        end
      end
    end
  end
end