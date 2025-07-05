# Working implementation example of the Toolset pattern

require 'json'
require 'sorbet-runtime'

module DSPy
  module Tools
    # Minimal implementation of Toolset base class
    class Toolset
      extend T::Sig
      
      class << self
        def expose_tool(method_name, tool_name: nil, description: nil)
          @exposed_tools ||= {}
          @exposed_tools[method_name] = {
            tool_name: tool_name || "#{toolset_name}_#{method_name}",
            description: description || "#{method_name} operation"
          }
        end
        
        def toolset_name(name = nil)
          @toolset_name = name if name
          @toolset_name || self.name.split('::').last.gsub(/Toolset$/, '').downcase
        end
        
        def to_tools
          instance = new
          (@exposed_tools || {}).map do |method_name, config|
            ToolProxy.new(instance, method_name, config[:tool_name], config[:description])
          end
        end
      end
      
      # Simplified ToolProxy that acts like a regular tool
      class ToolProxy
        attr_reader :name, :description
        
        def initialize(instance, method_name, tool_name, description)
          @instance = instance
          @method_name = method_name
          @name = tool_name
          @description = description
        end
        
        def call(**kwargs)
          @instance.send(@method_name, **kwargs)
        end
        
        def schema
          # Simplified schema generation for the example
          method = @instance.method(@method_name)
          params = method.parameters
          
          properties = {}
          required = []
          
          params.each do |type, name|
            if type == :keyreq
              properties[name] = { type: "string", description: "Parameter #{name}" }
              required << name.to_s
            elsif type == :key
              properties[name] = { type: "string", description: "Parameter #{name} (optional)" }
            end
          end
          
          {
            name: @name,
            description: @description,
            parameters: {
              type: "object",
              properties: properties,
              required: required
            }
          }.to_json
        end
      end
    end
    
    # Example: Knowledge Base Toolset
    class KnowledgeBaseToolset < Toolset
      toolset_name "kb"
      
      expose_tool :add_fact, description: "Add a new fact to the knowledge base"
      expose_tool :query, description: "Query facts by topic"
      expose_tool :update_fact, description: "Update an existing fact"
      expose_tool :list_topics, description: "List all topics in the knowledge base"
      expose_tool :export, tool_name: "kb_export_json", description: "Export knowledge base as JSON"
      
      def initialize
        @facts = {}
        @fact_id_counter = 0
      end
      
      def add_fact(topic:, content:, source: nil)
        @fact_id_counter += 1
        fact_id = "fact_#{@fact_id_counter}"
        
        @facts[topic] ||= []
        @facts[topic] << {
          id: fact_id,
          content: content,
          source: source,
          created_at: Time.now.to_s
        }
        
        "Added fact #{fact_id} to topic '#{topic}'"
      end
      
      def query(topic:, limit: 10)
        facts = @facts[topic] || []
        facts.take(limit).map { |f| f[:content] }
      end
      
      def update_fact(fact_id:, content:)
        @facts.each do |topic, facts|
          fact = facts.find { |f| f[:id] == fact_id }
          if fact
            fact[:content] = content
            fact[:updated_at] = Time.now.to_s
            return "Updated fact #{fact_id}"
          end
        end
        "Fact #{fact_id} not found"
      end
      
      def list_topics
        @facts.keys
      end
      
      def export
        @facts.to_json
      end
    end
  end
end

# Simulated ReAct Agent interaction
class SimulatedAgent
  def initialize(tools)
    @tools = tools.each_with_object({}) { |tool, hash| hash[tool.name] = tool }
  end
  
  def show_available_tools
    puts "Available tools:"
    @tools.each do |name, tool|
      puts "\n#{name}: #{tool.description}"
      schema = JSON.parse(tool.schema)
      puts "Parameters: #{schema['parameters']['properties'].keys.join(', ')}"
    end
  end
  
  def execute_action(tool_name, args)
    tool = @tools[tool_name]
    return "Tool '#{tool_name}' not found" unless tool
    
    tool.call(**args.transform_keys(&:to_sym))
  end
end

# Example usage demonstrating how an LLM would interact
puts "=== Knowledge Base Toolset Demo ==="
puts

# Create toolset and convert to tools
kb = DSPy::Tools::KnowledgeBaseToolset.new
kb_tools = kb.class.to_tools

# Create agent with the tools
agent = SimulatedAgent.new(kb_tools)
agent.show_available_tools

puts "\n=== Simulating LLM Tool Usage ==="

# LLM adds facts
puts "\n1. Adding facts about Ruby:"
result = agent.execute_action("kb_add_fact", {
  "topic" => "ruby",
  "content" => "Ruby is a dynamic, object-oriented programming language",
  "source" => "ruby-lang.org"
})
puts "   Result: #{result}"

result = agent.execute_action("kb_add_fact", {
  "topic" => "ruby",
  "content" => "Ruby was created by Yukihiro Matsumoto in 1995",
  "source" => "wikipedia"
})
puts "   Result: #{result}"

result = agent.execute_action("kb_add_fact", {
  "topic" => "rails",
  "content" => "Rails is a web framework written in Ruby",
  "source" => "rubyonrails.org"
})
puts "   Result: #{result}"

# LLM queries facts
puts "\n2. Querying facts about Ruby:"
facts = agent.execute_action("kb_query", { "topic" => "ruby", "limit" => 5 })
facts.each { |fact| puts "   - #{fact}" }

# LLM lists topics
puts "\n3. Listing all topics:"
topics = agent.execute_action("kb_list_topics", {})
puts "   Topics: #{topics.join(', ')}"

# LLM exports data
puts "\n4. Exporting knowledge base:"
export = agent.execute_action("kb_export_json", {})
puts "   Export preview: #{export[0..100]}..."

puts "\n=== Example LLM Prompts and Actions ==="
puts
puts "User: 'Store information about Ruby being object-oriented'"
puts "LLM Thought: I need to add this fact to the knowledge base"
puts "LLM Action: kb_add_fact"
puts "LLM Action Input: {\"topic\": \"ruby\", \"content\": \"Ruby is object-oriented\"}"
puts
puts "User: 'What do you know about Ruby?'"
puts "LLM Thought: I should query the knowledge base for Ruby facts"
puts "LLM Action: kb_query"
puts "LLM Action Input: {\"topic\": \"ruby\"}"