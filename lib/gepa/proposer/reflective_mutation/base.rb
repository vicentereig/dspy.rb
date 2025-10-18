# frozen_string_literal: true

require 'sorbet-runtime'

module GEPA
  module Proposer
    module ReflectiveMutation
      extend T::Sig

      CandidateSelector = T.type_alias { T.proc.params(state: GEPA::Core::State).returns(Integer) }

      ComponentSelector = T.type_alias do
        T.proc.params(
          state: GEPA::Core::State,
          trajectories: T::Array[T.untyped],
          subsample_scores: T::Array[Float],
          candidate_idx: Integer,
          candidate: T::Hash[String, String]
        ).returns(T::Array[String])
      end

      BatchSampler = T.type_alias do
        T.proc.params(trainset_size: Integer, iteration: Integer).returns(T::Array[Integer])
      end

      LanguageModel = T.type_alias { T.proc.params(prompt: String).returns(String) }

      class Signature < T::Struct
        extend T::Sig

        const :prompt_template, String
        const :input_keys, T::Array[String]
        const :output_keys, T::Array[String]
        const :prompt_renderer, T.proc.params(arg0: T::Hash[String, T.untyped]).returns(String)
        const :output_extractor, T.proc.params(arg0: String).returns(T::Hash[String, String])

        sig do
          params(lm: LanguageModel, input_dict: T::Hash[String, T.untyped]).returns(T::Hash[String, String])
        end
        def self.run(lm, input_dict)
          full_prompt = prompt_renderer.call(input_dict)
          output = lm.call(full_prompt).strip
          output_extractor.call(output)
        end
      end
    end
  end
end
