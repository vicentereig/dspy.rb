# GitHub Assistant Example

This example demonstrates how to use DSPy.rb's GitHub CLI Toolset to create an intelligent assistant that can perform various GitHub operations through natural language commands.

## Features

The GitHub Assistant can:

- **Issue Management**: List, search, and get details of GitHub issues
- **Pull Request Operations**: List, search, and get details of pull requests  
- **Repository Analysis**: Get repository statistics and information
- **API Interactions**: Make arbitrary GitHub API requests
- **Multi-Step Tasks**: Perform complex analysis combining multiple operations

## Prerequisites

1. **GitHub CLI**: Install and authenticate the GitHub CLI
   ```bash
   # Install GitHub CLI (macOS)
   brew install gh
   
   # Or download from: https://cli.github.com/
   
   # Authenticate
   gh auth login
   ```

2. **API Keys**: Set up your LLM provider API key
   ```bash
   # For OpenAI
   export OPENAI_API_KEY=your-openai-key
   
   # Or for Anthropic
   export ANTHROPIC_API_KEY=your-anthropic-key
   ```

3. **Dependencies**: Install Ruby gems
   ```bash
   bundle install
   ```

## Usage

### Demo Mode (Default)

Run the demo to see various GitHub operations:

```bash
ruby examples/github-assistant/github_assistant.rb
# or
ruby examples/github-assistant/github_assistant.rb demo
```

The demo will execute several predefined tasks:
- Repository analysis
- Issue searching with labels
- Pull request overview
- API exploration
- Multi-step comparative analysis

### Interactive Mode

Start an interactive session where you can ask questions:

```bash
ruby examples/github-assistant/github_assistant.rb interactive
```

Example interactions:
```
You: List the recent issues from microsoft/vscode
You: Find pull requests in rails/rails that need review
You: Get statistics about the golang/go repository
You: Compare issue activity vs PR activity in facebook/react
```

## Example Tasks

Here are some example tasks you can try:

### Repository Exploration
- "Get basic information about the microsoft/vscode repository"
- "How many stars and forks does the rails/rails repository have?"
- "What's the current activity level in the nodejs/node repository?"

### Issue Management
- "List the 10 most recent open issues from facebook/react"
- "Find issues labeled 'bug' in the golang/go repository"
- "Get details about issue #123 from microsoft/vscode"

### Pull Request Analysis
- "List open pull requests in rails/rails"
- "Find pull requests that might be ready for review"
- "Compare the number of open issues vs open PRs"

### Advanced Operations
- "Use the API to get contributor statistics for kubernetes/kubernetes"
- "Analyze the health of the rust-lang/rust repository"
- "Find the most discussed issues in the last month"

## Error Handling

The assistant gracefully handles common errors:

- **Authentication issues**: Prompts to run `gh auth login`
- **Non-existent repositories**: Reports the error clearly
- **Invalid issue/PR numbers**: Handles not found cases
- **Rate limiting**: Includes delays between operations
- **Network issues**: Provides informative error messages

## Customization

You can customize the assistant by:

1. **Modifying the signature**: Edit the `GitHubAssistant` class to add more fields
2. **Adding more tools**: Combine with other DSPy toolsets
3. **Changing the LM**: Use different language models
4. **Adjusting parameters**: Modify max_iterations, add system prompts, etc.

## Code Structure

- `github_assistant.rb`: Main script with demo and interactive modes
- `GitHubAssistant` signature: Defines the input/output structure
- `GitHubAssistantDemo` class: Contains the demo logic and interactive mode
- Error handling and CLI argument parsing

## Tips for Best Results

1. **Be specific**: Include repository names in your requests
2. **Use natural language**: The assistant understands conversational requests
3. **Complex tasks**: Break down complex analysis into specific questions
4. **Repository format**: Use `owner/repository` format for repositories
5. **Be patient**: Some operations may take time due to API calls

## Troubleshooting

- **"gh command not found"**: Install GitHub CLI
- **"Not authenticated"**: Run `gh auth login`
- **"No API key found"**: Set OPENAI_API_KEY or ANTHROPIC_API_KEY
- **Rate limiting**: Add delays between requests or use smaller batch sizes