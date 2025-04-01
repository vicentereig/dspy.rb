# frozen_string_literal: true

# Gemfile (inline)
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  ruby '3.3.6'

  gem 'faraday', '~> 2.7'
  gem 'faraday-retry'
  gem 'ruby-openai', '~> 6.0'
  gem 'dotenv'
end

require 'dotenv'
require 'openai'
require 'faraday'
require 'faraday/retry'
require 'json'
require 'dotenv/load'

# Load environment variables from .env file
Dotenv.load


# ReACT Agent class
class ReactAgent
  # TODO: turn this into a Signature
  THINKING_TEMPLATE = <<~PROMPT
    You are a problem-solving agent that follows the ReACT framework: Reasoning and Acting.
    For each step of solving a problem, you will:
    1. Think about the current state and what to do next
    2. Act by executing one of the available tools
    3. Observe the result of your action
    
    Available tools:
    - search(query): Search for information on a topic
    - calculate(expression): Calculate a mathematical expression
    
    Respond in the following format:
    Thought: I need to reason about the problem
    Action: tool_name(parameters)
    
    The current problem to solve is: {{problem}}
    
    Current state: {{state}}
  PROMPT

  def initialize(openai_client)
    @openai = openai_client
    @state = { observations: [], steps_taken: 0 }
  end

  def solve(problem)
    @problem = problem
    puts "🤔 Solving problem: #{problem}"

    # ReACT loop
    while @state[:steps_taken] < 5  # Limit to prevent infinite loops
      # 1 thinks, and reasons about the tool
      reasoning_step = think
      # thoughts.reasoning
      action_step = extract_action(reasoning_step)
      break unless action_step
      # runs the action
      observation = execute_action(action_step)
      update_state(observation)

      puts "\t\n--- Step #{@state[:steps_taken]} ---"
      puts "\t🧠 Thought: #{reasoning_step}"
      puts "\t🛠️ Action: #{action_step[:tool]}(#{action_step[:params]})"
      puts "\t👁️ Observation: #{observation}"
    end

    # Final answer
    final_result = generate_final_answer
    puts "\n✅ Final answer: #{final_result}"
    final_result
  end

  private

  def think

    # when I've turn the Thinking template in a Signature
    # then I can turn this into a DSPy::Predict module
    # https://github.com/stanfordnlp/dspy/blob/main/dspy/predict/react.py#L66-L67
    #  it performs an extra pass "extracting" with chain of thought :thinking face:
    #  seems that the decision of using a tool is encoded in the reasoning
    prompt = THINKING_TEMPLATE
               .gsub('{{problem}}', @problem)
               .gsub('{{state}}', @state.to_json)

    response = @openai.chat(
      parameters: {
        model: "gpt-4o",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.2
      }
    )

    response.dig("choices", 0, "message", "content")
  end

  def extract_action(reasoning)
    action_match = reasoning.match(/Action: (\w+)\((.+)\)/)
    return nil unless action_match

    {
      tool: action_match[1],
      params: action_match[2].strip
    }
  end

  def execute_action(action)
    case action[:tool]
    when "search"
      search(action[:params])
    when "calculate"
      calculate(action[:params])
    else
      "Error: Unknown tool #{action[:tool]}"
    end
  end

  def search(query)
    3200
  end

  def calculate(expression)
    # Simple calculator - in real implementation, use a safer evaluation method
    result = eval(expression)
    "Calculation result: #{result}"
  rescue => e
    "Error calculating: #{e.message}"
  end

  def update_state(observation)
    @state[:observations] << observation
    @state[:steps_taken] += 1
  end

  def generate_final_answer
    prompt = <<~PROMPT
      Based on the following observations, provide a final answer to the problem.
      
      Problem: #{@problem}
      Observations: #{@state[:observations].join("\n")}
      
      Final answer:
    PROMPT

    response = @openai.chat(
      parameters: {
        model: "gpt-4o",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.2
      }
    )

    response.dig("choices", 0, "message", "content")
  end
end

# Usage example
def main
  _problem = "X es la poblacion total de Espana e Y es la poblacion total de Francia. Z = Y+X es la poblacion total. Cuanto vale z?"
  problem = "What is the result of compounding 5000 dollars at 7% interest annually for 10 years, and then dividing that by the average monthly rent in San Francisco?"
  # Initialize OpenAI client
  openai = OpenAI::Client.new(
    access_token: ENV.fetch('OPENAI_API_KEY')
  )
  agent = ReactAgent.new(openai)
  result = agent.solve(problem)

  puts "\nProblem solved!"
end

main if __FILE__ == $PROGRAM_NAME
