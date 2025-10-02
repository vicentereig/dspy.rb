# frozen_string_literal: true

require 'spec_helper'
require 'dspy/tools/github_cli_toolset'

RSpec.describe DSPy::Tools::GitHubCLIToolset do
  let(:toolset) { described_class.new }

  describe 'class setup' do
    it 'has correct toolset name' do
      expect(described_class.toolset_name).to eq('github')
    end

    it 'exposes expected tools' do
      tools = described_class.to_tools
      tool_names = tools.map(&:name)
      
      expected_names = [
        'github_list_issues',
        'github_list_prs',
        'github_get_issue',
        'github_get_pr',
        'github_api_request'
      ]
      
      expect(tool_names).to match_array(expected_names)
    end
  end

  describe 'enum types' do
    describe 'IssueState' do
      it 'has expected values' do
        expect(DSPy::Tools::IssueState::Open.serialize).to eq('open')
        expect(DSPy::Tools::IssueState::Closed.serialize).to eq('closed')
        expect(DSPy::Tools::IssueState::All.serialize).to eq('all')
      end
    end

    describe 'PRState' do
      it 'has expected values' do
        expect(DSPy::Tools::PRState::Open.serialize).to eq('open')
        expect(DSPy::Tools::PRState::Closed.serialize).to eq('closed')
        expect(DSPy::Tools::PRState::Merged.serialize).to eq('merged')
        expect(DSPy::Tools::PRState::All.serialize).to eq('all')
      end
    end

    describe 'ReviewState' do
      it 'has expected values' do
        expect(DSPy::Tools::ReviewState::Approve.serialize).to eq('approve')
        expect(DSPy::Tools::ReviewState::Comment.serialize).to eq('comment')
        expect(DSPy::Tools::ReviewState::RequestChanges.serialize).to eq('request-changes')
      end
    end
  end

  describe 'struct types' do
    describe 'IssueDetails' do
      it 'can be created with expected properties' do
        issue = DSPy::Tools::IssueDetails.new(
          number: 123,
          title: 'Test Issue',
          state: 'open',
          body: 'Test body',
          url: 'https://github.com/owner/repo/issues/123',
          labels: ['bug', 'enhancement'],
          assignees: ['user1', 'user2']
        )

        expect(issue.number).to eq(123)
        expect(issue.title).to eq('Test Issue')
        expect(issue.state).to eq('open')
        expect(issue.body).to eq('Test body')
        expect(issue.url).to eq('https://github.com/owner/repo/issues/123')
        expect(issue.labels).to eq(['bug', 'enhancement'])
        expect(issue.assignees).to eq(['user1', 'user2'])
      end
    end

    describe 'PRDetails' do
      it 'can be created with expected properties' do
        pr = DSPy::Tools::PRDetails.new(
          number: 456,
          title: 'Test PR',
          state: 'open',
          body: 'Test PR body',
          url: 'https://github.com/owner/repo/pull/456',
          base: 'main',
          head: 'feature-branch',
          mergeable: true
        )

        expect(pr.number).to eq(456)
        expect(pr.title).to eq('Test PR')
        expect(pr.state).to eq('open')
        expect(pr.body).to eq('Test PR body')
        expect(pr.url).to eq('https://github.com/owner/repo/pull/456')
        expect(pr.base).to eq('main')
        expect(pr.head).to eq('feature-branch')
        expect(pr.mergeable).to eq(true)
      end
    end
  end

  describe 'schema generation' do
    it 'generates correct enum schemas' do
      schema = described_class.schema_for_method(:list_issues)
      state_schema = schema[:properties][:state]

      expect(state_schema[:type]).to eq('string')
      expect(state_schema[:enum]).to contain_exactly('open', 'closed', 'all')
    end

    it 'generates correct array schemas' do
      schema = described_class.schema_for_method(:list_issues)
      labels_schema = schema[:properties][:labels]

      expect(labels_schema[:type]).to eq('array')
      expect(labels_schema[:items][:type]).to eq('string')
    end

    it 'handles nilable parameters correctly' do
      schema = described_class.schema_for_method(:get_issue)
      repo_schema = schema[:properties][:repo]

      expect(repo_schema[:type]).to eq(['string', 'null'])
    end
  end

  describe 'private helper methods' do
    describe '#shell_escape' do
      it 'wraps strings in double quotes and escapes internal double quotes' do
        result = toolset.send(:shell_escape, 'test "quoted" text')
        expect(result).to eq('"test \\"quoted\\" text"')
      end

      it 'wraps strings with single quotes in double quotes' do
        result = toolset.send(:shell_escape, "test 'quoted' text")
        expect(result).to eq("\"test 'quoted' text\"")
      end
    end

    describe '#build_gh_command' do
      it 'prepends gh to command arguments' do
        result = toolset.send(:build_gh_command, ['issue', 'list'])
        expect(result).to eq(['gh', 'issue', 'list'])
      end
    end

    describe '#execute_command' do
      it 'returns success hash for successful commands' do
        allow(toolset).to receive(:`).and_return("output\n")
        allow(Process).to receive(:last_status).and_return(double(success?: true))

        result = toolset.send(:execute_command, 'echo test')

        expect(result[:success]).to be true
        expect(result[:output]).to eq("output\n")
        expect(result[:error]).to eq('')
      end

      it 'returns error hash for failed commands' do
        allow(toolset).to receive(:`).and_return("error message\n")
        allow(Process).to receive(:last_status).and_return(double(success?: false))

        result = toolset.send(:execute_command, 'false')

        expect(result[:success]).to be false
        expect(result[:output]).to eq('')
        expect(result[:error]).to eq("error message\n")
      end
    end

    describe 'JSON parsing methods' do
      describe '#parse_issue_list' do
        it 'parses empty issue list' do
          result = toolset.send(:parse_issue_list, '[]')
          expect(result).to eq('No issues found')
        end

        it 'parses issue list with data' do
          json_data = [{
            'number' => 123,
            'title' => 'Test Issue',
            'state' => 'open',
            'url' => 'https://github.com/owner/repo/issues/123',
            'labels' => [{'name' => 'bug'}],
            'assignees' => [{'login' => 'user1'}]
          }].to_json

          result = toolset.send(:parse_issue_list, json_data)

          expect(result).to include('Found 1 issue(s)')
          expect(result).to include('#123: Test Issue (open)')
          expect(result).to include('Labels: bug')
          expect(result).to include('Assignees: user1')
        end

        it 'handles malformed JSON' do
          result = toolset.send(:parse_issue_list, 'invalid json')
          expect(result).to include('Failed to parse issues data')
        end
      end

      describe '#parse_pr_list' do
        it 'parses empty PR list' do
          result = toolset.send(:parse_pr_list, '[]')
          expect(result).to eq('No pull requests found')
        end

        it 'parses PR list with data' do
          json_data = [{
            'number' => 456,
            'title' => 'Test PR',
            'state' => 'open',
            'url' => 'https://github.com/owner/repo/pull/456',
            'headRefName' => 'feature',
            'baseRefName' => 'main'
          }].to_json

          result = toolset.send(:parse_pr_list, json_data)

          expect(result).to include('Found 1 pull request(s)')
          expect(result).to include('#456: Test PR (open)')
          expect(result).to include('feature → main')
        end

        it 'handles malformed JSON' do
          result = toolset.send(:parse_pr_list, 'invalid json')
          expect(result).to include('Failed to parse pull requests data')
        end
      end

      describe '#parse_issue_details' do
        it 'parses issue details' do
          json_data = {
            'number' => 123,
            'title' => 'Test Issue',
            'state' => 'open',
            'body' => 'Issue description',
            'url' => 'https://github.com/owner/repo/issues/123',
            'labels' => [{'name' => 'bug'}],
            'assignees' => [{'login' => 'user1'}]
          }.to_json

          result = toolset.send(:parse_issue_details, json_data)

          expect(result).to include('Issue #123: Test Issue')
          expect(result).to include('State: open')
          expect(result).to include('Labels: bug')
          expect(result).to include('Assignees: user1')
          expect(result).to include('Issue description')
        end

        it 'handles missing body' do
          json_data = {
            'number' => 123,
            'title' => 'Test Issue',
            'state' => 'open',
            'body' => nil,
            'url' => 'https://github.com/owner/repo/issues/123',
            'labels' => [],
            'assignees' => []
          }.to_json

          result = toolset.send(:parse_issue_details, json_data)

          expect(result).to include('No description provided')
        end

        it 'handles malformed JSON' do
          result = toolset.send(:parse_issue_details, 'invalid json')
          expect(result).to include('Failed to parse issue details')
        end
      end

      describe '#parse_pr_details' do
        it 'parses PR details' do
          json_data = {
            'number' => 456,
            'title' => 'Test PR',
            'state' => 'open',
            'body' => 'PR description',
            'url' => 'https://github.com/owner/repo/pull/456',
            'headRefName' => 'feature',
            'baseRefName' => 'main',
            'mergeable' => true
          }.to_json

          result = toolset.send(:parse_pr_details, json_data)

          expect(result).to include('Pull Request #456: Test PR')
          expect(result).to include('State: open')
          expect(result).to include('Branch: feature → main')
          expect(result).to include('Mergeable: Yes')
          expect(result).to include('PR description')
        end

        it 'handles missing body and false mergeable' do
          json_data = {
            'number' => 456,
            'title' => 'Test PR',
            'state' => 'open',
            'body' => nil,
            'url' => 'https://github.com/owner/repo/pull/456',
            'headRefName' => 'feature',
            'baseRefName' => 'main',
            'mergeable' => false
          }.to_json

          result = toolset.send(:parse_pr_details, json_data)

          expect(result).to include('No description provided')
          expect(result).to include('Mergeable: No')
        end

        it 'handles malformed JSON' do
          result = toolset.send(:parse_pr_details, 'invalid json')
          expect(result).to include('Failed to parse pull request details')
        end
      end
    end
  end

  describe 'method command building' do
    before do
      allow(toolset).to receive(:execute_command).and_return({
        success: true,
        output: 'success',
        error: ''
      })
    end


    describe '#list_issues' do
      it 'builds correct command with default parameters' do
        allow(toolset).to receive(:execute_command).and_return({
          success: true,
          output: '[]',
          error: ''
        })

        expect(toolset).to receive(:execute_command).with(
          "gh issue list --json number,title,state,labels,assignees,url --state open --limit 20"
        )

        toolset.list_issues
      end

      it 'builds correct command with custom parameters' do
        allow(toolset).to receive(:execute_command).and_return({
          success: true,
          output: '[]',
          error: ''
        })

        expect(toolset).to receive(:execute_command).with(
          "gh issue list --json number,title,state,labels,assignees,url --state closed --limit 50 --label \"bug\" --label \"enhancement\" --assignee \"user1\" --repo \"owner/repo\""
        )

        toolset.list_issues(
          state: DSPy::Tools::IssueState::Closed,
          labels: ['bug', 'enhancement'],
          assignee: 'user1',
          repo: 'owner/repo',
          limit: 50
        )
      end
    end


    describe '#api_request' do
      it 'builds correct API request with defaults' do
        expect(toolset).to receive(:execute_command).with(
          "gh api repos/{owner}/{repo}/issues --method GET"
        )

        toolset.api_request(endpoint: 'repos/{owner}/{repo}/issues')
      end

      it 'rejects non-GET methods for read-only access' do
        result = toolset.api_request(
          endpoint: 'repos/{owner}/{repo}/issues',
          method: 'POST',
          fields: { 'title' => 'New Issue', 'body' => 'Description' },
          repo: 'owner/repo'
        )
        
        expect(result).to eq("Error: Only GET requests are allowed for read-only access")
      end
      
      it 'allows GET method with fields and repo' do
        expect(toolset).to receive(:execute_command).with(
          "gh api repos/{owner}/{repo}/issues --method GET -f state=\"open\" -f sort=\"updated\" --repo \"owner/repo\""
        )

        toolset.api_request(
          endpoint: 'repos/{owner}/{repo}/issues',
          method: 'GET',
          fields: { 'state' => 'open', 'sort' => 'updated' },
          repo: 'owner/repo'
        )
      end
    end
  end
end