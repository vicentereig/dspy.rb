# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Callbacks Integration' do
  # Simple test module that doesn't require LLM
  class CallbackTestModule < DSPy::Module
    attr_reader :call_log

    def initialize
      @call_log = []
    end

    def forward(input:)
      @call_log << :forward
      "result: #{input}"
    end
  end

  describe 'with DSPy::Module subclasses' do
    context 'before callback' do
      let(:module_class) do
        Class.new(CallbackTestModule) do
          before :setup_context

          private

          def setup_context
            @call_log << :setup_context
          end
        end
      end

      it 'executes before callback before forward' do
        mod = module_class.new
        result = mod.forward(input: "test")

        expect(mod.call_log).to eq([:setup_context, :forward])
        expect(result).to eq("result: test")
      end
    end

    context 'after callback' do
      let(:module_class) do
        Class.new(CallbackTestModule) do
          after :log_result

          private

          def log_result
            @call_log << :log_result
          end
        end
      end

      it 'executes after callback after forward' do
        mod = module_class.new
        result = mod.forward(input: "test")

        expect(mod.call_log).to eq([:forward, :log_result])
        expect(result).to eq("result: test")
      end
    end

    context 'around callback' do
      let(:module_class) do
        Class.new(CallbackTestModule) do
          around :manage_context

          private

          def manage_context
            @call_log << :before_forward
            result = yield
            @call_log << :after_forward
            result
          end
        end
      end

      it 'wraps forward execution' do
        mod = module_class.new
        result = mod.forward(input: "test")

        expect(mod.call_log).to eq([:before_forward, :forward, :after_forward])
        expect(result).to eq("result: test")
      end
    end

    context 'combined callbacks' do
      let(:module_class) do
        Class.new(CallbackTestModule) do
          attr_accessor :metrics

          before :setup_metrics
          after :log_metrics
          around :manage_context

          def initialize
            super
            @metrics = {}
          end

          private

          def setup_metrics
            @call_log << :setup_metrics
            @metrics[:start_time] = Time.now
          end

          def log_metrics
            @call_log << :log_metrics
            @metrics[:duration] = Time.now - @metrics[:start_time]
          end

          def manage_context
            @call_log << :before_context
            result = yield
            @call_log << :after_context
            result
          end
        end
      end

      it 'executes all callbacks in correct order' do
        mod = module_class.new
        result = mod.forward(input: "test")

        # Order: before -> around_before -> forward -> around_after -> after
        expect(mod.call_log).to eq([
          :setup_metrics,
          :before_context,
          :forward,
          :after_context,
          :log_metrics
        ])
        expect(result).to eq("result: test")
        expect(mod.metrics[:duration]).to be_a(Float)
      end
    end

    context 'inheritance' do
      let(:base_class) do
        Class.new(CallbackTestModule) do
          before :base_setup

          private

          def base_setup
            @call_log << :base_setup
          end
        end
      end

      let(:derived_class) do
        Class.new(base_class) do
          before :derived_setup

          private

          def derived_setup
            @call_log << :derived_setup
          end
        end
      end

      it 'inherits parent callbacks' do
        mod = derived_class.new
        result = mod.forward(input: "test")

        expect(mod.call_log).to eq([:base_setup, :derived_setup, :forward])
        expect(result).to eq("result: test")
      end
    end
  end
end
