# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tools Enum Support', :vcr do
  # Define test enum for calculator operations
  class CalculatorOperation < T::Enum
    enums do
      Add = new('add')
      Subtract = new('subtract') 
      Multiply = new('multiply')
      Divide = new('divide')
    end
  end

  # Define test tool using enum parameter
  class CalculatorTool < DSPy::Tools::Base
    sig { params(operation: CalculatorOperation, num1: Float, num2: Float).returns(T.any(Float, String)) }
    def call(operation:, num1:, num2:)
      case operation
      when CalculatorOperation::Add then num1 + num2
      when CalculatorOperation::Subtract then num1 - num2
      when CalculatorOperation::Multiply then num1 * num2
      when CalculatorOperation::Divide 
        return "Error: Division by zero" if num2 == 0
        num1 / num2
      else
        "Error: Unknown operation"
      end
    end
  end

  # Define test struct using enum for complex scenarios
  class CalculationRequest < T::Struct
    prop :operation, CalculatorOperation
    prop :operands, T::Array[Float]
    prop :precision, T.nilable(Integer), default: nil
  end

  class AdvancedCalculatorTool < DSPy::Tools::Base
    sig { params(request: CalculationRequest).returns(T.any(Float, String)) }
    def call(request:)
      return "Error: Need exactly 2 operands" unless request.operands.length == 2
      
      num1, num2 = request.operands
      result = case request.operation
               when CalculatorOperation::Add then num1 + num2
               when CalculatorOperation::Subtract then num1 - num2
               when CalculatorOperation::Multiply then num1 * num2
               when CalculatorOperation::Divide 
                 return "Error: Division by zero" if num2 == 0
                 num1 / num2
               end
      
      if request.precision
        result.round(request.precision)
      else
        result
      end
    end
  end

  describe DSPy::Tools::Base do
    describe '#call_schema' do
      it 'generates correct JSON schema for enum parameters' do
        tool = CalculatorTool.new
        schema = tool.call_schema

        expect(schema[:type]).to eq('function')
        expect(schema[:function][:name]).to eq('call')
        
        properties = schema[:function][:parameters][:properties]
        operation_schema = properties[:operation]
        
        expect(operation_schema[:type]).to eq('string')
        expect(operation_schema[:enum]).to contain_exactly('add', 'subtract', 'multiply', 'divide')
      end

      it 'generates correct schema for struct with enum properties' do
        tool = AdvancedCalculatorTool.new
        schema = tool.call_schema

        properties = schema[:function][:parameters][:properties]
        request_schema = properties[:request]
        
        expect(request_schema[:type]).to eq('object')
        expect(request_schema[:properties][:operation][:type]).to eq('string')
        expect(request_schema[:properties][:operation][:enum]).to contain_exactly('add', 'subtract', 'multiply', 'divide')
        expect(request_schema[:properties][:operands][:type]).to eq('array')
        expect(request_schema[:properties][:operands][:items][:type]).to eq('number')
        expect(request_schema[:properties][:precision][:type]).to eq(['integer', 'null'])
      end
    end

    describe '#dynamic_call' do
      it 'converts string to enum instance for basic enum parameter' do
        tool = CalculatorTool.new
        
        result = tool.dynamic_call({
          'operation' => 'add',
          'num1' => 5.0,
          'num2' => 3.0
        })
        
        expect(result).to eq(8.0)
      end

      it 'handles all enum values correctly' do
        tool = CalculatorTool.new
        
        expect(tool.dynamic_call({'operation' => 'add', 'num1' => 5, 'num2' => 3})).to eq(8)
        expect(tool.dynamic_call({'operation' => 'subtract', 'num1' => 5, 'num2' => 3})).to eq(2)
        expect(tool.dynamic_call({'operation' => 'multiply', 'num1' => 5, 'num2' => 3})).to eq(15)
        expect(tool.dynamic_call({'operation' => 'divide', 'num1' => 6, 'num2' => 3})).to eq(2)
      end

      it 'handles division by zero' do
        tool = CalculatorTool.new
        result = tool.dynamic_call({'operation' => 'divide', 'num1' => 5, 'num2' => 0})
        expect(result).to eq("Error: Division by zero")
      end

      it 'raises error for invalid enum values' do
        tool = CalculatorTool.new

        expect {
          tool.dynamic_call({'operation' => 'invalid', 'num1' => 5, 'num2' => 3})
        }.to raise_error(TypeError, /Expected type|Can't set|Invalid enum/)
      end

      it 'converts enum in nested struct parameters' do
        tool = AdvancedCalculatorTool.new
        
        result = tool.dynamic_call({
          'request' => {
            'operation' => 'multiply',
            'operands' => [4.0, 7.0],
            'precision' => 2
          }
        })
        
        expect(result).to eq(28.0)
      end

      it 'handles optional precision in struct' do
        tool = AdvancedCalculatorTool.new
        
        result = tool.dynamic_call({
          'request' => {
            'operation' => 'divide',
            'operands' => [7.0, 3.0]
          }
        })
        
        expect(result).to be_within(0.001).of(2.333)
      end
    end
  end

  describe DSPy::Tools::Toolset do
    class CalculatorToolset < DSPy::Tools::Toolset
      tool :calculate

      sig { params(operation: CalculatorOperation, num1: Float, num2: Float).returns(T.any(Float, String)) }
      def calculate(operation:, num1:, num2:)
        case operation
        when CalculatorOperation::Add then num1 + num2
        when CalculatorOperation::Subtract then num1 - num2
        when CalculatorOperation::Multiply then num1 * num2
        when CalculatorOperation::Divide 
          return "Error: Division by zero" if num2 == 0
          num1 / num2
        else
          "Error: Unknown operation"
        end
      end

      tool :advanced_calculate

      sig { params(request: CalculationRequest).returns(T.any(Float, String)) }
      def advanced_calculate(request:)
        return "Error: Need exactly 2 operands" unless request.operands.length == 2
        
        num1, num2 = request.operands
        result = case request.operation
                 when CalculatorOperation::Add then num1 + num2
                 when CalculatorOperation::Subtract then num1 - num2
                 when CalculatorOperation::Multiply then num1 * num2
                 when CalculatorOperation::Divide 
                   return "Error: Division by zero" if num2 == 0
                   num1 / num2
                 end
        
        if request.precision
          result.round(request.precision)
        else
          result
        end
      end
    end

    it 'generates correct schemas for tools with enums' do
      toolset_class = CalculatorToolset
      schema = toolset_class.schema_for_method(:calculate)

      expect(schema[:type]).to eq(:object)
      
      operation_schema = schema[:properties][:operation]
      expect(operation_schema[:type]).to eq("string")
      expect(operation_schema[:enum]).to contain_exactly('add', 'subtract', 'multiply', 'divide')
    end

    it 'handles dynamic calls with enum conversion' do
      toolset = CalculatorToolset.new
      tool_proxy = CalculatorToolset.to_tools.find { |tool| tool.name.include?('calculate') && !tool.name.include?('advanced') }
      
      result = tool_proxy.dynamic_call({
        'operation' => 'subtract',
        'num1' => 10,
        'num2' => 4
      })
      
      expect(result).to eq(6)
    end
  end
end