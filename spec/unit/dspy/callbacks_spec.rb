# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Callbacks do
  # Test module that includes callbacks
  let(:test_class) do
    Class.new do
      include DSPy::Callbacks

      attr_reader :call_log

      def initialize
        @call_log = []
      end

      # The method we'll add callbacks to
      def forward(input)
        @call_log << :forward
        "result: #{input}"
      end

      private

      def setup_context
        @call_log << :setup_context
      end

      def log_result
        @call_log << :log_result
      end

      def manage_memory
        @call_log << :before_manage_memory
        result = yield
        @call_log << :after_manage_memory
        result
      end
    end
  end

  describe '.create_before_callback' do
    it 'creates a before callback registration method' do
      test_class.create_before_callback(:forward)

      expect(test_class).to respond_to(:before)
    end

    it 'allows registering before callbacks' do
      test_class.create_before_callback(:forward)

      expect { test_class.before(:setup_context) }.not_to raise_error
    end
  end

  describe '.create_after_callback' do
    it 'creates an after callback registration method' do
      test_class.create_after_callback(:forward)

      expect(test_class).to respond_to(:after)
    end

    it 'allows registering after callbacks' do
      test_class.create_after_callback(:forward)

      expect { test_class.after(:log_result) }.not_to raise_error
    end
  end

  describe '.create_around_callback' do
    it 'creates an around callback registration method' do
      test_class.create_around_callback(:forward)

      expect(test_class).to respond_to(:around)
    end

    it 'allows registering around callbacks' do
      test_class.create_around_callback(:forward)

      expect { test_class.around(:manage_memory) }.not_to raise_error
    end
  end

  describe 'callback execution' do
    context 'before callbacks' do
      before do
        test_class.create_before_callback(:forward)
        test_class.before(:setup_context)
      end

      it 'executes before callback before the method' do
        instance = test_class.new
        instance.forward('test')

        expect(instance.call_log).to eq([:setup_context, :forward])
      end

      it 'returns the original method result' do
        instance = test_class.new
        result = instance.forward('test')

        expect(result).to eq('result: test')
      end
    end

    context 'after callbacks' do
      before do
        test_class.create_after_callback(:forward)
        test_class.after(:log_result)
      end

      it 'executes after callback after the method' do
        instance = test_class.new
        instance.forward('test')

        expect(instance.call_log).to eq([:forward, :log_result])
      end
    end

    context 'around callbacks' do
      before do
        test_class.create_around_callback(:forward)
        test_class.around(:manage_memory)
      end

      it 'wraps the method execution' do
        instance = test_class.new
        instance.forward('test')

        expect(instance.call_log).to eq([
          :before_manage_memory,
          :forward,
          :after_manage_memory
        ])
      end

      it 'returns the original method result' do
        instance = test_class.new
        result = instance.forward('test')

        expect(result).to eq('result: test')
      end
    end

    context 'combined callbacks' do
      before do
        test_class.create_before_callback(:forward)
        test_class.create_after_callback(:forward)
        test_class.create_around_callback(:forward)

        test_class.before(:setup_context)
        test_class.after(:log_result)
        test_class.around(:manage_memory)
      end

      it 'executes all callbacks in correct order' do
        instance = test_class.new
        instance.forward('test')

        # Order: before -> around_before -> forward -> around_after -> after
        expect(instance.call_log).to eq([
          :setup_context,
          :before_manage_memory,
          :forward,
          :after_manage_memory,
          :log_result
        ])
      end
    end

    context 'multiple callbacks of same type' do
      before do
        test_class.create_before_callback(:forward)

        test_class.class_eval do
          def first_setup
            @call_log << :first_setup
          end

          def second_setup
            @call_log << :second_setup
          end
        end

        test_class.before(:first_setup)
        test_class.before(:second_setup)
      end

      it 'executes callbacks in registration order' do
        instance = test_class.new
        instance.forward('test')

        expect(instance.call_log).to eq([
          :first_setup,
          :second_setup,
          :forward
        ])
      end
    end
  end

  describe 'inheritance' do
    let(:parent_class) do
      Class.new do
        include DSPy::Callbacks

        attr_reader :call_log

        def initialize
          @call_log = []
        end

        create_before_callback(:forward)
        before(:parent_setup)

        def forward(input)
          @call_log << :forward
          "result: #{input}"
        end

        private

        def parent_setup
          @call_log << :parent_setup
        end
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        before(:child_setup)

        private

        def child_setup
          @call_log << :child_setup
        end
      end
    end

    it 'inherits parent callbacks' do
      instance = child_class.new
      instance.forward('test')

      expect(instance.call_log).to include(:parent_setup)
    end

    it 'executes both parent and child callbacks' do
      instance = child_class.new
      instance.forward('test')

      expect(instance.call_log).to eq([
        :parent_setup,
        :child_setup,
        :forward
      ])
    end
  end
end
