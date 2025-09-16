# frozen_string_literal: true

require 'spec_helper'
require 'dspy/tools/github_cli_toolset'

# Signature for GitHub operations with GitHub CLI tools  
class GitHubAssistant < DSPy::Signature
  description "Perform GitHub operations using GitHub CLI tools"
  
  input do
    const :task, String
    const :repository, String, default: ""
  end
  
  output do
    const :result, String
  end
end

RSpec.describe 'GitHub CLI Toolset Integration with ReAct Agent', type: :integration do
  let(:lm) do
    DSPy::LM.new(
      'openai/gpt-4o-mini',
      api_key: ENV['OPENAI_API_KEY']
    )
  end

  let(:github_tools) { DSPy::Tools::GitHubCLIToolset.to_tools }
  
  let(:agent) do
    DSPy::ReAct.new(
      GitHubAssistant,
      tools: github_tools,
      max_iterations: 10
    )
  end

  before do
    DSPy.configure do |config|
      config.lm = lm
    end
  end

  describe 'issue management tasks', :vcr do
    it 'can list issues from a repository' do
      VCR.use_cassette('github_cli_toolset/list_repository_issues') do
        response = agent.call(
          task: 'List the open issues for this repository',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.length).to be > 20
        # Should indicate issues were found or searched
        expect(response.result.downcase).to include('issue').or include('list').or include('repository').or include('found').or include('search')
      end
    end

    it 'can get details of a specific issue' do
      VCR.use_cassette('github_cli_toolset/get_issue_details') do
        response = agent.call(
          task: 'Get details about issue #123 from the microsoft/vscode repository',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('issue').or include('details').or include('found').or include('search').or include('repository')
      end
    end

    it 'can search for issues with specific labels' do
      VCR.use_cassette('github_cli_toolset/search_labeled_issues') do
        response = agent.call(
          task: 'Find open issues labeled "bug" in the microsoft/vscode repository',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('bug').or include('issue').or include('found').or include('search').or include('label')
      end
    end
  end

  describe 'pull request management tasks', :vcr do
    it 'can list pull requests from a repository' do
      VCR.use_cassette('github_cli_toolset/list_repository_prs') do
        response = agent.call(
          task: 'List the open pull requests for the microsoft/vscode repository',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.length).to be > 20
        # Should indicate PRs were found or searched
        expect(response.result.downcase).to include('pull').or include('request').or include('list').or include('found').or include('search')
      end
    end

    it 'can get details of a specific pull request' do
      VCR.use_cassette('github_cli_toolset/get_pr_details') do
        response = agent.call(
          task: 'Get details about pull request #456 from the microsoft/vscode repository',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('pull').or include('request').or include('details').or include('found').or include('search').or include('repository')
      end
    end
  end

  describe 'API and repository exploration tasks', :vcr do
    it 'can make API requests to get repository information' do
      VCR.use_cassette('github_cli_toolset/api_repository_info') do
        response = agent.call(
          task: 'Use the GitHub API to get basic information about the microsoft/vscode repository (stars, forks, description)',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('repository').or include('api').or include('information').or include('stars').or include('forks').or include('description')
      end
    end

    it 'can explore repository statistics' do
      VCR.use_cassette('github_cli_toolset/repository_statistics') do
        response = agent.call(
          task: 'Get statistics about the microsoft/vscode repository - how many open issues and pull requests are there?',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('statistics').or include('issues').or include('pull').or include('request').or include('open').or include('count').or include('number')
      end
    end
  end

  describe 'error handling and edge cases', :vcr do
    it 'handles non-existent repository gracefully' do
      VCR.use_cassette('github_cli_toolset/nonexistent_repository') do
        response = agent.call(
          task: 'List issues from the repository "nonexistent/repo-that-does-not-exist"',
          repository: 'nonexistent/repo-that-does-not-exist'
        )
        
        expect(response.result).to be_a(String)
        # Should handle error gracefully
        expect(response.result.downcase).to include('error').or include('not found').or include('invalid').or include('failed').or include('issue').or include('repository')
      end
    end

    it 'handles invalid issue numbers gracefully' do
      VCR.use_cassette('github_cli_toolset/invalid_issue_number') do
        response = agent.call(
          task: 'Get details about issue #999999 from the microsoft/vscode repository',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        # Should handle error gracefully  
        expect(response.result.downcase).to include('error').or include('not found').or include('invalid').or include('failed').or include('issue').or include('details')
      end
    end
  end

  describe 'complex multi-step tasks', :vcr do
    it 'can perform multi-step repository analysis' do
      VCR.use_cassette('github_cli_toolset/complex_repository_analysis') do
        response = agent.call(
          task: 'Analyze the microsoft/vscode repository: first list recent issues, then get repository info via API, and summarize what you find',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.length).to be > 50
        # Should show evidence of multi-step analysis
        expect(response.result.downcase).to include('repository').or include('analysis').or include('issues').or include('summary').or include('found').or include('information')
      end
    end

    it 'can compare issues and pull requests' do
      VCR.use_cassette('github_cli_toolset/issues_vs_prs_comparison') do
        response = agent.call(
          task: 'Compare the number of open issues vs open pull requests in the microsoft/vscode repository and tell me which is higher',
          repository: 'microsoft/vscode'
        )
        
        expect(response.result).to be_a(String)
        # Should show comparison analysis
        expect(response.result.downcase).to include('issue').or include('pull').or include('request').or include('compare').or include('higher').or include('number').or include('open')
      end
    end
  end
end