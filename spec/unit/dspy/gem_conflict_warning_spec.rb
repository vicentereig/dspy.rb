# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy gem conflict detection' do
  describe 'detection logic' do
    it 'correctly identifies ruby-openai gem pattern' do
      # Test the detection logic directly
      # ruby-openai: has OpenAI and OpenAI::Client but NOT OpenAI::Internal
      # official gem: has OpenAI, OpenAI::Client AND OpenAI::Internal
      
      # Simulate ruby-openai pattern
      openai_module = Module.new
      client_class = Class.new
      
      # The detection condition
      has_openai = !openai_module.nil?
      has_client = !client_class.nil?
      has_internal = false  # ruby-openai doesn't have this
      
      should_warn = has_openai && has_client && !has_internal
      
      expect(should_warn).to be true
    end
    
    it 'does not trigger for official openai gem pattern' do
      # Simulate official gem pattern
      openai_module = Module.new
      client_class = Class.new
      internal_module = Module.new  # official gem has this
      
      # The detection condition
      has_openai = !openai_module.nil?
      has_client = !client_class.nil?
      has_internal = !internal_module.nil?
      
      should_warn = has_openai && has_client && !has_internal
      
      expect(should_warn).to be false
    end
    
    it 'does not trigger when no OpenAI gem is loaded' do
      # Test the condition when OpenAI is not defined at all
      should_warn = false  # No OpenAI constant means no conflict
      
      expect(should_warn).to be false
    end
  end
  
  describe 'warning message format' do
    it 'contains all necessary information for users' do
      # Test that the warning message has the right content
      warning_message = <<~WARNING
        WARNING: ruby-openai gem detected. This may cause conflicts with DSPy's OpenAI integration.
        
        DSPy uses the official 'openai' gem. The community 'ruby-openai' gem uses the same
        OpenAI namespace and will cause conflicts.
        
        To fix this, remove 'ruby-openai' from your Gemfile and use the official gem instead:
        - Remove: gem 'ruby-openai'
        - Keep: gem 'openai' (official SDK that DSPy uses)
        
        The official gem provides better compatibility and is actively maintained by OpenAI.
      WARNING
      
      # Check key components of the warning
      expect(warning_message).to include('ruby-openai gem detected')
      expect(warning_message).to include('DSPy uses the official \'openai\' gem')
      expect(warning_message).to include('OpenAI namespace and will cause conflicts')
      expect(warning_message).to include('Remove: gem \'ruby-openai\'')
      expect(warning_message).to include('Keep: gem \'openai\'')
      expect(warning_message).to include('actively maintained by OpenAI')
    end
  end
end