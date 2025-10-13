# frozen_string_literal: true

require 'spec_helper'
require 'dspy/propose/grounded_proposer'

RSpec.describe DSPy::Propose::GroundedProposer::Config, 'awareness flags' do
  describe 'initialization with Python-compatible parameters' do
    it 'has all Python awareness flags with correct defaults' do
      config = described_class.new

      # Python-compatible awareness flags (match Python defaults)
      expect(config.program_aware).to be(true)
      expect(config.use_dataset_summary).to be(true)
      expect(config.use_task_demos).to be(true)
      expect(config.use_tip).to be(true)
      expect(config.use_instruct_history).to be(true)

      # Additional parameters
      expect(config.num_demos_in_context).to eq(3)
      expect(config.view_data_batch_size).to eq(10)
      expect(config.set_tip_randomly).to be(true)
      expect(config.set_history_randomly).to be(true)
      expect(config.init_temperature).to eq(1.0)
      expect(config.verbose).to be(false)
    end

    it 'allows customization of awareness flags' do
      config = described_class.new
      config.program_aware = false
      config.use_dataset_summary = false
      config.use_task_demos = false
      config.use_tip = false
      config.use_instruct_history = false

      expect(config.program_aware).to be(false)
      expect(config.use_dataset_summary).to be(false)
      expect(config.use_task_demos).to be(false)
      expect(config.use_tip).to be(false)
      expect(config.use_instruct_history).to be(false)
    end

    it 'allows customization of additional parameters' do
      config = described_class.new
      config.num_demos_in_context = 5
      config.view_data_batch_size = 20
      config.set_tip_randomly = false
      config.set_history_randomly = false
      config.init_temperature = 0.7
      config.verbose = true

      expect(config.num_demos_in_context).to eq(5)
      expect(config.view_data_batch_size).to eq(20)
      expect(config.set_tip_randomly).to be(false)
      expect(config.set_history_randomly).to be(false)
      expect(config.init_temperature).to eq(0.7)
      expect(config.verbose).to be(true)
    end

    it 'does not have deprecated attributes' do
      config = described_class.new

      # These should be removed (not Python-compatible)
      expect(config).not_to respond_to(:use_task_description)
      expect(config).not_to respond_to(:use_input_output_analysis)
      expect(config).not_to respond_to(:use_few_shot_examples)
      expect(config).not_to respond_to(:max_examples_for_analysis)
      expect(config).not_to respond_to(:proposal_model)
    end
  end
end
