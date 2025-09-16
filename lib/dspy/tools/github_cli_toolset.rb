# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'
require_relative 'toolset'

module DSPy
  module Tools
    # Enums for GitHub CLI operations
    class IssueState < T::Enum
      enums do
        Open = new('open')
        Closed = new('closed') 
        All = new('all')
      end
    end

    class PRState < T::Enum
      enums do
        Open = new('open')
        Closed = new('closed')
        Merged = new('merged')
        All = new('all')
      end
    end

    class ReviewState < T::Enum
      enums do
        Approve = new('approve')
        Comment = new('comment')
        RequestChanges = new('request-changes')
      end
    end

    # Structs for complex return types
    class IssueDetails < T::Struct
      prop :number, Integer
      prop :title, String
      prop :state, String
      prop :body, String
      prop :url, String
      prop :labels, T::Array[String]
      prop :assignees, T::Array[String]
    end

    class PRDetails < T::Struct
      prop :number, Integer
      prop :title, String
      prop :state, String
      prop :body, String
      prop :url, String
      prop :base, String
      prop :head, String
      prop :mergeable, T::Boolean
    end

    # GitHub CLI toolset for common GitHub operations
    class GitHubCLIToolset < Toolset
      extend T::Sig

      toolset_name "github"

      # Expose methods as tools with descriptions
      tool :create_issue, description: "Create a new GitHub issue"
      tool :create_pr, description: "Create a new GitHub pull request"
      tool :list_issues, description: "List GitHub issues with optional filters"
      tool :list_prs, description: "List GitHub pull requests with optional filters"
      tool :get_issue, description: "Get details of a specific GitHub issue"
      tool :get_pr, description: "Get details of a specific GitHub pull request"
      tool :comment_on_issue, description: "Add a comment to a GitHub issue"
      tool :review_pr, description: "Add a review to a GitHub pull request"
      tool :api_request, description: "Make an arbitrary GitHub API request"

      sig { void }
      def initialize
        # No persistent state needed
      end

      sig { params(
        title: String,
        body: String,
        labels: T::Array[String],
        assignees: T::Array[String],
        repo: T.nilable(String)
      ).returns(String) }
      def create_issue(title:, body:, labels: [], assignees: [], repo: nil)
        cmd = build_gh_command(['issue', 'create'])
        cmd << ['--title', shell_escape(title)]
        cmd << ['--body', shell_escape(body)]
        
        labels.each { |label| cmd << ['--label', shell_escape(label)] }
        assignees.each { |assignee| cmd << ['--assignee', shell_escape(assignee)] }
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          "Issue created successfully: #{result[:output].strip}"
        else
          "Failed to create issue: #{result[:error]}"
        end
      rescue => e
        "Error creating issue: #{e.message}"
      end

      sig { params(
        title: String,
        body: String,
        base: String,
        head: String,
        repo: T.nilable(String)
      ).returns(String) }
      def create_pr(title:, body:, base:, head:, repo: nil)
        cmd = build_gh_command(['pr', 'create'])
        cmd << ['--title', shell_escape(title)]
        cmd << ['--body', shell_escape(body)]
        cmd << ['--base', shell_escape(base)]
        cmd << ['--head', shell_escape(head)]
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          "Pull request created successfully: #{result[:output].strip}"
        else
          "Failed to create pull request: #{result[:error]}"
        end
      rescue => e
        "Error creating pull request: #{e.message}"
      end

      sig { params(
        state: IssueState,
        labels: T::Array[String],
        assignee: T.nilable(String),
        repo: T.nilable(String),
        limit: Integer
      ).returns(String) }
      def list_issues(state: IssueState::Open, labels: [], assignee: nil, repo: nil, limit: 20)
        cmd = build_gh_command(['issue', 'list', '--json', 'number,title,state,labels,assignees,url'])
        cmd << ['--state', state.serialize]
        cmd << ['--limit', limit.to_s]
        
        labels.each { |label| cmd << ['--label', shell_escape(label)] }
        
        if assignee
          cmd << ['--assignee', shell_escape(assignee)]
        end
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          parse_issue_list(result[:output])
        else
          "Failed to list issues: #{result[:error]}"
        end
      rescue => e
        "Error listing issues: #{e.message}"
      end

      sig { params(
        state: PRState,
        author: T.nilable(String),
        base: T.nilable(String),
        repo: T.nilable(String),
        limit: Integer
      ).returns(String) }
      def list_prs(state: PRState::Open, author: nil, base: nil, repo: nil, limit: 20)
        cmd = build_gh_command(['pr', 'list', '--json', 'number,title,state,baseRefName,headRefName,url'])
        cmd << ['--state', state.serialize]
        cmd << ['--limit', limit.to_s]
        
        if author
          cmd << ['--author', shell_escape(author)]
        end
        
        if base
          cmd << ['--base', shell_escape(base)]
        end
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          parse_pr_list(result[:output])
        else
          "Failed to list pull requests: #{result[:error]}"
        end
      rescue => e
        "Error listing pull requests: #{e.message}"
      end

      sig { params(issue_number: Integer, repo: T.nilable(String)).returns(String) }
      def get_issue(issue_number:, repo: nil)
        cmd = build_gh_command(['issue', 'view', issue_number.to_s, '--json', 'number,title,state,body,labels,assignees,url'])
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          parse_issue_details(result[:output])
        else
          "Failed to get issue: #{result[:error]}"
        end
      rescue => e
        "Error getting issue: #{e.message}"
      end

      sig { params(pr_number: Integer, repo: T.nilable(String)).returns(String) }
      def get_pr(pr_number:, repo: nil)
        cmd = build_gh_command(['pr', 'view', pr_number.to_s, '--json', 'number,title,state,body,baseRefName,headRefName,mergeable,url'])
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          parse_pr_details(result[:output])
        else
          "Failed to get pull request: #{result[:error]}"
        end
      rescue => e
        "Error getting pull request: #{e.message}"
      end

      sig { params(
        issue_number: Integer,
        comment: String,
        repo: T.nilable(String)
      ).returns(String) }
      def comment_on_issue(issue_number:, comment:, repo: nil)
        cmd = build_gh_command(['issue', 'comment', issue_number.to_s])
        cmd << ['--body', shell_escape(comment)]
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          "Comment added successfully to issue ##{issue_number}"
        else
          "Failed to add comment: #{result[:error]}"
        end
      rescue => e
        "Error adding comment: #{e.message}"
      end

      sig { params(
        pr_number: Integer,
        review_type: ReviewState,
        comment: T.nilable(String),
        repo: T.nilable(String)
      ).returns(String) }
      def review_pr(pr_number:, review_type:, comment: nil, repo: nil)
        cmd = build_gh_command(['pr', 'review', pr_number.to_s])
        cmd << ['--' + review_type.serialize.tr('_', '-')]
        
        if comment
          cmd << ['--body', shell_escape(comment)]
        end
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          "Review added successfully to PR ##{pr_number}"
        else
          "Failed to add review: #{result[:error]}"
        end
      rescue => e
        "Error adding review: #{e.message}"
      end

      sig { params(
        endpoint: String,
        method: String,
        fields: T::Hash[String, String],
        repo: T.nilable(String)
      ).returns(String) }
      def api_request(endpoint:, method: 'GET', fields: {}, repo: nil)
        cmd = build_gh_command(['api', endpoint])
        cmd << ['--method', method.upcase]
        
        fields.each do |key, value|
          cmd << ['-f', "#{key}=#{shell_escape(value)}"]
        end
        
        if repo
          cmd << ['--repo', shell_escape(repo)]
        end

        result = execute_command(cmd.flatten.join(' '))
        
        if result[:success]
          result[:output]
        else
          "API request failed: #{result[:error]}"
        end
      rescue => e
        "Error making API request: #{e.message}"
      end

      private

      sig { params(args: T::Array[String]).returns(T::Array[String]) }
      def build_gh_command(args)
        ['gh'] + args
      end

      sig { params(str: String).returns(String) }
      def shell_escape(str)
        "\"#{str.gsub(/"/, '\\"')}\""
      end

      sig { params(cmd: String).returns(T::Hash[Symbol, T.untyped]) }
      def execute_command(cmd)
        output = `#{cmd} 2>&1`
        success = Process.last_status.success?
        
        {
          success: success,
          output: success ? output : '',
          error: success ? '' : output
        }
      end

      sig { params(json_output: String).returns(String) }
      def parse_issue_list(json_output)
        issues = JSON.parse(json_output)
        
        if issues.empty?
          "No issues found"
        else
          result = ["Found #{issues.length} issue(s):"]
          issues.each do |issue|
            labels = issue['labels']&.map { |l| l['name'] } || []
            assignees = issue['assignees']&.map { |a| a['login'] } || []
            
            result << "##{issue['number']}: #{issue['title']} (#{issue['state']})"
            result << "  Labels: #{labels.join(', ')}" unless labels.empty?
            result << "  Assignees: #{assignees.join(', ')}" unless assignees.empty?
            result << "  URL: #{issue['url']}"
            result << ""
          end
          result.join("\n")
        end
      rescue JSON::ParserError => e
        "Failed to parse issues data: #{e.message}"
      end

      sig { params(json_output: String).returns(String) }
      def parse_pr_list(json_output)
        prs = JSON.parse(json_output)
        
        if prs.empty?
          "No pull requests found"
        else
          result = ["Found #{prs.length} pull request(s):"]
          prs.each do |pr|
            result << "##{pr['number']}: #{pr['title']} (#{pr['state']})"
            result << "  #{pr['headRefName']} → #{pr['baseRefName']}"
            result << "  URL: #{pr['url']}"
            result << ""
          end
          result.join("\n")
        end
      rescue JSON::ParserError => e
        "Failed to parse pull requests data: #{e.message}"
      end

      sig { params(json_output: String).returns(String) }
      def parse_issue_details(json_output)
        issue = JSON.parse(json_output)
        labels = issue['labels']&.map { |l| l['name'] } || []
        assignees = issue['assignees']&.map { |a| a['login'] } || []
        
        result = []
        result << "Issue ##{issue['number']}: #{issue['title']}"
        result << "State: #{issue['state']}"
        result << "Labels: #{labels.join(', ')}" unless labels.empty?
        result << "Assignees: #{assignees.join(', ')}" unless assignees.empty?
        result << "URL: #{issue['url']}"
        result << ""
        result << "Body:"
        body = issue['body']
        result << (body && !body.empty? ? body : "No description provided")
        
        result.join("\n")
      rescue JSON::ParserError => e
        "Failed to parse issue details: #{e.message}"
      end

      sig { params(json_output: String).returns(String) }
      def parse_pr_details(json_output)
        pr = JSON.parse(json_output)
        
        result = []
        result << "Pull Request ##{pr['number']}: #{pr['title']}"
        result << "State: #{pr['state']}"
        result << "Branch: #{pr['headRefName']} → #{pr['baseRefName']}"
        result << "Mergeable: #{pr['mergeable'] ? 'Yes' : 'No'}"
        result << "URL: #{pr['url']}"
        result << ""
        result << "Body:"
        body = pr['body']
        result << (body && !body.empty? ? body : "No description provided")
        
        result.join("\n")
      rescue JSON::ParserError => e
        "Failed to parse pull request details: #{e.message}"
      end
    end
  end
end