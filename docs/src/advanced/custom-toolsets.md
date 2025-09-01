---
layout: docs
title: Custom Toolsets
description: Build advanced toolsets for specialized agent capabilities
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: Custom Toolsets
  url: "/advanced/custom-toolsets/"
nav:
  prev:
    name: Stateful Agents
    url: "/advanced/stateful-agents/"
  next:
    name: RAG
    url: "/advanced/rag/"
date: 2025-07-11 00:00:00 +0000
---
# Custom Toolsets

Custom toolsets allow you to extend agents with specialized capabilities by grouping related operations into cohesive tool collections. This guide covers advanced patterns for building production-ready toolsets.

## Toolset Architecture

### Base Toolset Structure

All custom toolsets inherit from `DSPy::Tools::Toolset`:

```ruby
class MyCustomToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  # Set the toolset name (used as prefix for tool names)
  toolset_name "my_custom"
  
  # Declare tools with descriptions
  tool :operation_one, description: "Performs the first operation"
  tool :operation_two, description: "Performs the second operation"
  
  # Initialize any required state
  def initialize
    @state = {}
  end
  
  # Implement tool methods with Sorbet signatures
  sig { params(input: String).returns(String) }
  def operation_one(input:)
    # Implementation
  end
  
  sig { params(value: Integer, multiplier: T.nilable(Integer)).returns(Integer) }
  def operation_two(value:, multiplier: nil)
    # Implementation
  end
end
```

### Tool Method Requirements

1. **Keyword Arguments**: All parameters must be keyword arguments
2. **Sorbet Signatures**: Required for automatic schema generation
3. **Return Values**: Must return serializable values (String, Integer, Hash, Array)
4. **Error Handling**: Should handle errors gracefully

## Production Toolset Examples

### 1. Simple Data Storage Toolset

```ruby
class DataStorageToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  toolset_name "data"
  
  tool :store_data, description: "Store data with a key"
  tool :retrieve_data, description: "Retrieve data by key"
  tool :list_keys, description: "List all stored keys"
  tool :delete_data, description: "Delete data by key"
  
  def initialize
    @data_store = {}
  end
  
  sig { params(key: String, value: String).returns(String) }
  def store_data(key:, value:)
    @data_store[key] = {
      value: value,
      stored_at: Time.now.iso8601
    }
    
    "Data stored successfully for key: #{key}"
  rescue => e
    "Error storing data: #{e.message}"
  end
  
  sig { params(key: String).returns(String) }
  def retrieve_data(key:)
    data = @data_store[key]
    
    if data
      {
        key: key,
        value: data[:value],
        stored_at: data[:stored_at]
      }.to_json
    else
      "No data found for key: #{key}"
    end
  rescue => e
    "Error retrieving data: #{e.message}"
  end
  
  sig { returns(String) }
  def list_keys
    keys = @data_store.keys
    
    {
      keys: keys,
      count: keys.length
    }.to_json
  rescue => e
    "Error listing keys: #{e.message}"
  end
  
  sig { params(key: String).returns(String) }
  def delete_data(key:)
    if @data_store.delete(key)
      "Data deleted successfully for key: #{key}"
    else
      "No data found for key: #{key}"
    end
  rescue => e
    "Error deleting data: #{e.message}"
  end
end
```

### 2. File System Operations Toolset

```ruby
class FileSystemToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  toolset_name "fs"
  
  tool :read_file, description: "Read contents of a file"
  tool :write_file, description: "Write content to a file"
  tool :list_directory, description: "List files in a directory"
  tool :file_exists, description: "Check if a file exists"
  tool :create_directory, description: "Create a directory"
  tool :delete_file, description: "Delete a file"
  tool :file_info, description: "Get file information"
  
  def initialize(base_path:, allowed_extensions: [])
    @base_path = File.expand_path(base_path)
    @allowed_extensions = allowed_extensions
  end
  
  sig { params(file_path: String).returns(String) }
  def read_file(file_path:)
    full_path = validate_and_resolve_path(file_path)
    
    raise "File does not exist" unless File.exist?(full_path)
    raise "Path is not a file" unless File.file?(full_path)
    
    File.read(full_path)
  rescue => e
    "Error reading file: #{e.message}"
  end
  
  sig { params(file_path: String, content: String).returns(String) }
  def write_file(file_path:, content:)
    full_path = validate_and_resolve_path(file_path)
    validate_file_extension(full_path)
    
    # Create directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(full_path))
    
    File.write(full_path, content)
    "File written successfully: #{file_path}"
  rescue => e
    "Error writing file: #{e.message}"
  end
  
  sig { params(directory_path: String).returns(String) }
  def list_directory(directory_path:)
    full_path = validate_and_resolve_path(directory_path)
    
    raise "Directory does not exist" unless File.exist?(full_path)
    raise "Path is not a directory" unless File.directory?(full_path)
    
    entries = Dir.entries(full_path).reject { |entry| entry.start_with?('.') }
    
    file_info = entries.map do |entry|
      entry_path = File.join(full_path, entry)
      {
        name: entry,
        type: File.directory?(entry_path) ? "directory" : "file",
        size: File.directory?(entry_path) ? nil : File.size(entry_path)
      }
    end
    
    file_info.to_json
  rescue => e
    "Error listing directory: #{e.message}"
  end
  
  sig { params(file_path: String).returns(String) }
  def file_exists(file_path:)
    full_path = validate_and_resolve_path(file_path)
    File.exist?(full_path) ? "true" : "false"
  rescue => e
    "Error checking file existence: #{e.message}"
  end
  
  sig { params(directory_path: String).returns(String) }
  def create_directory(directory_path:)
    full_path = validate_and_resolve_path(directory_path)
    
    FileUtils.mkdir_p(full_path)
    "Directory created: #{directory_path}"
  rescue => e
    "Error creating directory: #{e.message}"
  end
  
  sig { params(file_path: String).returns(String) }
  def delete_file(file_path:)
    full_path = validate_and_resolve_path(file_path)
    
    raise "File does not exist" unless File.exist?(full_path)
    
    File.delete(full_path)
    "File deleted: #{file_path}"
  rescue => e
    "Error deleting file: #{e.message}"
  end
  
  sig { params(file_path: String).returns(String) }
  def file_info(file_path:)
    full_path = validate_and_resolve_path(file_path)
    
    raise "File does not exist" unless File.exist?(full_path)
    
    stat = File.stat(full_path)
    
    info = {
      path: file_path,
      size: stat.size,
      modified: stat.mtime.iso8601,
      type: File.directory?(full_path) ? "directory" : "file",
      permissions: stat.mode.to_s(8)
    }
    
    info.to_json
  rescue => e
    "Error getting file info: #{e.message}"
  end
  
  private
  
  def validate_and_resolve_path(path)
    # Resolve relative to base path
    full_path = File.expand_path(path, @base_path)
    
    # Security check: ensure path is within base path
    unless full_path.start_with?(@base_path)
      raise "Path outside allowed directory"
    end
    
    full_path
  end
  
  def validate_file_extension(full_path)
    return if @allowed_extensions.empty?
    
    extension = File.extname(full_path).downcase
    unless @allowed_extensions.include?(extension)
      raise "File extension not allowed: #{extension}"
    end
  end
end
```

### 3. HTTP API Client Toolset

```ruby
class HttpApiToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  toolset_name "http"
  
  tool :get_request, description: "Make a GET request to an API endpoint"
  tool :post_request, description: "Make a POST request with JSON data"
  tool :put_request, description: "Make a PUT request with JSON data"
  tool :delete_request, description: "Make a DELETE request"
  tool :head_request, description: "Make a HEAD request to check endpoint status"
  
  def initialize(base_url:, api_key: nil, timeout: 30)
    @base_url = base_url.chomp('/')
    @api_key = api_key
    @timeout = timeout
  end
  
  sig { params(endpoint: String, params: T::Hash[String, T.untyped]).returns(String) }
  def get_request(endpoint:, params: {})
    url = build_url(endpoint, params)
    
    response = make_request(:get, url)
    format_response(response)
  rescue => e
    "Error making GET request: #{e.message}"
  end
  
  sig { params(endpoint: String, data: T::Hash[String, T.untyped]).returns(String) }
  def post_request(endpoint:, data:)
    url = build_url(endpoint)
    
    response = make_request(:post, url, data)
    format_response(response)
  rescue => e
    "Error making POST request: #{e.message}"
  end
  
  sig { params(endpoint: String, data: T::Hash[String, T.untyped]).returns(String) }
  def put_request(endpoint:, data:)
    url = build_url(endpoint)
    
    response = make_request(:put, url, data)
    format_response(response)
  rescue => e
    "Error making PUT request: #{e.message}"
  end
  
  sig { params(endpoint: String).returns(String) }
  def delete_request(endpoint:)
    url = build_url(endpoint)
    
    response = make_request(:delete, url)
    format_response(response)
  rescue => e
    "Error making DELETE request: #{e.message}"
  end
  
  sig { params(endpoint: String).returns(String) }
  def head_request(endpoint:)
    url = build_url(endpoint)
    
    response = make_request(:head, url)
    {
      status: response.code,
      headers: response.headers,
      content_length: response.headers['content-length']
    }.to_json
  rescue => e
    "Error making HEAD request: #{e.message}"
  end
  
  private
  
  def build_url(endpoint, params = {})
    url = "#{@base_url}#{endpoint}"
    
    unless params.empty?
      query_string = params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join('&')
      url += "?#{query_string}"
    end
    
    url
  end
  
  def make_request(method, url, data = nil)
    uri = URI(url)
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = @timeout
    
    request = case method
    when :get
      Net::HTTP::Get.new(uri)
    when :post
      req = Net::HTTP::Post.new(uri)
      req.body = data.to_json if data
      req['Content-Type'] = 'application/json'
      req
    when :put
      req = Net::HTTP::Put.new(uri)
      req.body = data.to_json if data
      req['Content-Type'] = 'application/json'
      req
    when :delete
      Net::HTTP::Delete.new(uri)
    when :head
      Net::HTTP::Head.new(uri)
    end
    
    # Add authentication if available
    request['Authorization'] = "Bearer #{@api_key}" if @api_key
    
    response = http.request(request)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP #{response.code}: #{response.message}"
    end
    
    response
  end
  
  def format_response(response)
    {
      status: response.code.to_i,
      headers: response.to_hash,
      body: parse_response_body(response.body)
    }.to_json
  end
  
  def parse_response_body(body)
    return nil if body.nil? || body.empty?
    
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end
end
```

### 4. Text Processing Toolset

```ruby
class TextProcessingToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  toolset_name "text"
  
  tool :extract_keywords, description: "Extract keywords from text"
  tool :summarize_text, description: "Create a summary of text"
  tool :count_words, description: "Count words in text"
  tool :sentiment_analysis, description: "Analyze sentiment of text"
  tool :extract_entities, description: "Extract named entities from text"
  tool :clean_text, description: "Clean and normalize text"
  
  def initialize
    # Initialize any required processing tools
  end
  
  sig { params(text: String, max_keywords: Integer).returns(String) }
  def extract_keywords(text:, max_keywords: 10)
    words = text.downcase.split(/\W+/)
    
    # Simple keyword extraction (frequency-based)
    word_counts = words.each_with_object(Hash.new(0)) { |word, hash| hash[word] += 1 }
    
    # Filter out common words (basic stopwords)
    stopwords = %w[the and or but in on at to for of with by from]
    keywords = word_counts.reject { |word, _| stopwords.include?(word) || word.length < 3 }
    
    # Get top keywords
    top_keywords = keywords.sort_by { |_, count| -count }.first(max_keywords)
    
    {
      keywords: top_keywords.map { |word, count| { word: word, frequency: count } },
      total_words: words.length
    }.to_json
  rescue => e
    "Error extracting keywords: #{e.message}"
  end
  
  sig { params(text: String, max_sentences: Integer).returns(String) }
  def summarize_text(text:, max_sentences: 3)
    sentences = text.split(/[.!?]+/).map(&:strip).reject(&:empty?)
    
    return text if sentences.length <= max_sentences
    
    # Simple extractive summarization (first, middle, last sentences)
    summary_sentences = []
    summary_sentences << sentences.first
    
    if max_sentences > 2 && sentences.length > 2
      middle_index = sentences.length / 2
      summary_sentences << sentences[middle_index]
    end
    
    if max_sentences > 1 && sentences.length > 1
      summary_sentences << sentences.last
    end
    
    {
      summary: summary_sentences.join('. ') + '.',
      original_sentences: sentences.length,
      summary_sentences: summary_sentences.length
    }.to_json
  rescue => e
    "Error summarizing text: #{e.message}"
  end
  
  sig { params(text: String).returns(String) }
  def count_words(text:)
    words = text.split(/\s+/)
    characters = text.length
    sentences = text.split(/[.!?]+/).length
    paragraphs = text.split(/\n\s*\n/).length
    
    {
      words: words.length,
      characters: characters,
      sentences: sentences,
      paragraphs: paragraphs
    }.to_json
  rescue => e
    "Error counting words: #{e.message}"
  end
  
  sig { params(text: String).returns(String) }
  def sentiment_analysis(text:)
    # Simple rule-based sentiment analysis
    positive_words = %w[good great excellent amazing wonderful fantastic happy love like]
    negative_words = %w[bad terrible awful horrible hate dislike sad angry worse]
    
    words = text.downcase.split(/\W+/)
    
    positive_count = words.count { |word| positive_words.include?(word) }
    negative_count = words.count { |word| negative_words.include?(word) }
    
    score = positive_count - negative_count
    
    sentiment = if score > 0
      "positive"
    elsif score < 0
      "negative"
    else
      "neutral"
    end
    
    {
      sentiment: sentiment,
      score: score,
      positive_words: positive_count,
      negative_words: negative_count
    }.to_json
  rescue => e
    "Error analyzing sentiment: #{e.message}"
  end
  
  sig { params(text: String).returns(String) }
  def extract_entities(text:)
    # Simple entity extraction using patterns
    
    # Email pattern
    emails = text.scan(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
    
    # URL pattern
    urls = text.scan(/https?:\/\/[^\s]+/)
    
    # Phone number pattern (basic)
    phones = text.scan(/\b\d{3}-\d{3}-\d{4}\b/)
    
    # Date pattern (basic)
    dates = text.scan(/\b\d{1,2}\/\d{1,2}\/\d{4}\b/)
    
    {
      emails: emails,
      urls: urls,
      phone_numbers: phones,
      dates: dates
    }.to_json
  rescue => e
    "Error extracting entities: #{e.message}"
  end
  
  sig { params(text: String).returns(String) }
  def clean_text(text:)
    # Basic text cleaning
    cleaned = text.dup
    
    # Remove extra whitespace
    cleaned.gsub!(/\s+/, ' ')
    
    # Remove leading/trailing whitespace
    cleaned.strip!
    
    # Remove special characters (keep basic punctuation)
    cleaned.gsub!(/[^\w\s.,!?;:'"()-]/, '')
    
    {
      original_length: text.length,
      cleaned_length: cleaned.length,
      cleaned_text: cleaned
    }.to_json
  rescue => e
    "Error cleaning text: #{e.message}"
  end
end
```

## Advanced Patterns

### 1. Stateful Toolsets

```ruby
class StatefulToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  toolset_name "stateful"
  
  tool :start_session, description: "Start a new session"
  tool :add_to_session, description: "Add data to current session"
  tool :get_session_data, description: "Get all session data"
  tool :end_session, description: "End current session"
  
  def initialize
    @sessions = {}
  end
  
  sig { params(session_id: String).returns(String) }
  def start_session(session_id:)
    @sessions[session_id] = {
      started_at: Time.now,
      data: {},
      operations: []
    }
    
    "Session #{session_id} started"
  end
  
  sig { params(session_id: String, key: String, value: String).returns(String) }
  def add_to_session(session_id:, key:, value:)
    session = @sessions[session_id]
    return "Session not found" unless session
    
    session[:data][key] = value
    session[:operations] << {
      operation: "add",
      key: key,
      value: value,
      timestamp: Time.now
    }
    
    "Added #{key} to session #{session_id}"
  end
  
  sig { params(session_id: String).returns(String) }
  def get_session_data(session_id:)
    session = @sessions[session_id]
    return "Session not found" unless session
    
    {
      session_id: session_id,
      started_at: session[:started_at],
      data: session[:data],
      operations_count: session[:operations].length
    }.to_json
  end
  
  sig { params(session_id: String).returns(String) }
  def end_session(session_id:)
    session = @sessions.delete(session_id)
    return "Session not found" unless session
    
    "Session #{session_id} ended"
  end
end
```

### 2. Async Toolsets

```ruby
class AsyncToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  toolset_name "async"
  
  tool :start_background_task, description: "Start a background task"
  tool :check_task_status, description: "Check the status of a background task"
  tool :get_task_result, description: "Get the result of a completed task"
  
  def initialize
    @tasks = {}
  end
  
  sig { params(task_id: String, operation: String, data: T::Hash[String, T.untyped]).returns(String) }
  def start_background_task(task_id:, operation:, data:)
    thread = Thread.new do
      begin
        # Simulate some work
        sleep(2)
        
        result = case operation
        when "process_data"
          { processed: data, timestamp: Time.now }
        when "calculate"
          { result: data.values.sum, timestamp: Time.now }
        else
          { error: "Unknown operation" }
        end
        
        @tasks[task_id][:status] = "completed"
        @tasks[task_id][:result] = result
        @tasks[task_id][:completed_at] = Time.now
      rescue => e
        @tasks[task_id][:status] = "failed"
        @tasks[task_id][:error] = e.message
      end
    end
    
    @tasks[task_id] = {
      status: "running",
      started_at: Time.now,
      thread: thread
    }
    
    "Task #{task_id} started"
  end
  
  sig { params(task_id: String).returns(String) }
  def check_task_status(task_id:)
    task = @tasks[task_id]
    return "Task not found" unless task
    
    {
      task_id: task_id,
      status: task[:status],
      started_at: task[:started_at],
      completed_at: task[:completed_at]
    }.to_json
  end
  
  sig { params(task_id: String).returns(String) }
  def get_task_result(task_id:)
    task = @tasks[task_id]
    return "Task not found" unless task
    
    case task[:status]
    when "running"
      "Task is still running"
    when "completed"
      task[:result].to_json
    when "failed"
      "Task failed: #{task[:error]}"
    else
      "Unknown task status"
    end
  end
end
```

### 3. Validation and Security

```ruby
class SecureToolset < DSPy::Tools::Toolset
  extend T::Sig
  
  toolset_name "secure"
  
  tool :validate_input, description: "Validate input according to rules"
  tool :sanitize_data, description: "Sanitize data for safe processing"
  tool :encrypt_data, description: "Encrypt sensitive data"
  tool :decrypt_data, description: "Decrypt encrypted data"
  
  def initialize(encryption_key:)
    @encryption_key = encryption_key
  end
  
  sig { params(data: String, rules: T::Array[String]).returns(String) }
  def validate_input(data:, rules:)
    errors = []
    
    rules.each do |rule|
      case rule
      when "not_empty"
        errors << "Data cannot be empty" if data.strip.empty?
      when "max_length_100"
        errors << "Data too long (max 100 chars)" if data.length > 100
      when "alphanumeric"
        errors << "Data must be alphanumeric" unless data.match?(/\A[a-zA-Z0-9\s]+\z/)
      when "email"
        errors << "Invalid email format" unless data.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      end
    end
    
    {
      valid: errors.empty?,
      errors: errors,
      data: data
    }.to_json
  end
  
  sig { params(data: String).returns(String) }
  def sanitize_data(data:)
    sanitized = data.dup
    
    # Remove potentially dangerous characters
    sanitized.gsub!(/[<>]/, '')
    
    # Escape special characters
    sanitized.gsub!(/[&]/, '&amp;')
    sanitized.gsub!(/["]/, '&quot;')
    sanitized.gsub!(/[']/, '&#39;')
    
    # Limit length
    sanitized = sanitized[0, 1000] if sanitized.length > 1000
    
    {
      original: data,
      sanitized: sanitized,
      changes_made: data != sanitized
    }.to_json
  end
  
  sig { params(data: String).returns(String) }
  def encrypt_data(data:)
    # Simple encryption (in production, use proper encryption)
    encrypted = Base64.encode64(data.bytes.map { |b| b ^ @encryption_key }.pack('C*'))
    
    {
      encrypted: encrypted.strip,
      original_length: data.length
    }.to_json
  rescue => e
    "Error encrypting data: #{e.message}"
  end
  
  sig { params(encrypted_data: String).returns(String) }
  def decrypt_data(encrypted_data:)
    # Simple decryption (in production, use proper decryption)
    decoded = Base64.decode64(encrypted_data)
    decrypted = decoded.bytes.map { |b| b ^ @encryption_key }.pack('C*')
    
    {
      decrypted: decrypted,
      decrypted_length: decrypted.length
    }.to_json
  rescue => e
    "Error decrypting data: #{e.message}"
  end
end
```

## Testing Custom Toolsets

### Unit Testing

```ruby
RSpec.describe DataStorageToolset do
  let(:toolset) { described_class.new }
  
  describe '#store_data' do
    it 'stores data successfully' do
      result = toolset.store_data(key: "test_key", value: "test_value")
      expect(result).to include("stored successfully")
    end
  end
  
  describe '#retrieve_data' do
    it 'retrieves stored data' do
      toolset.store_data(key: "test_key", value: "test_value")
      result = toolset.retrieve_data(key: "test_key")
      
      parsed = JSON.parse(result)
      expect(parsed["key"]).to eq("test_key")
      expect(parsed["value"]).to eq("test_value")
    end
    
    it 'handles missing keys gracefully' do
      result = toolset.retrieve_data(key: "missing_key")
      expect(result).to include("No data found")
    end
  end
  
  describe '#list_keys' do
    it 'lists all stored keys' do
      toolset.store_data(key: "key1", value: "value1")
      toolset.store_data(key: "key2", value: "value2")
      
      result = toolset.list_keys
      parsed = JSON.parse(result)
      
      expect(parsed["keys"]).to contain_exactly("key1", "key2")
      expect(parsed["count"]).to eq(2)
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Custom Toolset Integration" do
  let(:toolset) { FileSystemToolset.new(base_path: "/tmp/test") }
  let(:tools) { toolset.class.to_tools }
  
  let(:agent) do
    DSPy::ReAct.new(
      TestSignature,
      tools: tools,
      max_iterations: 3
    )
  end
  
  before do
    FileUtils.mkdir_p("/tmp/test")
  end
  
  after do
    FileUtils.rm_rf("/tmp/test")
  end
  
  it 'can use file operations in agent workflow' do
    result = agent.call(
      query: "Create a file called 'test.txt' with content 'Hello World'"
    )
    
    expect(result.answer).to include("file created")
    expect(File.exist?("/tmp/test/test.txt")).to be true
  end
end
```

## Best Practices

### 1. Error Handling

```ruby
# Good: Return error messages instead of raising exceptions
def risky_operation(data:)
  validate_data(data)
  result = perform_operation(data)
  "Success: #{result}"
rescue ValidationError => e
  "Validation failed: #{e.message}"
rescue => e
  "Operation failed: #{e.message}"
end

# Bad: Let exceptions bubble up
def risky_operation(data:)
  validate_data(data)  # Could raise exception
  perform_operation(data)  # Could raise exception
end
```

### 2. Input Validation

```ruby
# Good: Validate all inputs
def process_data(data:, options: {})
  raise ArgumentError, "Data cannot be empty" if data.nil? || data.empty?
  raise ArgumentError, "Options must be a hash" unless options.is_a?(Hash)
  
  # Process data...
end

# Bad: Assume inputs are valid
def process_data(data:, options: {})
  # Process data without validation
end
```

### 3. Resource Management

```ruby
# Good: Clean up resources
def initialize(database_url:)
  @connection = establish_connection(database_url)
end

def cleanup
  @connection&.close
end

# Bad: Leave resources open
def initialize(database_url:)
  @connection = establish_connection(database_url)
  # No cleanup mechanism
end
```

### 4. Documentation

```ruby
# Good: Clear tool descriptions
tool :complex_operation, description: "Performs complex data transformation on the input dataset"

# Bad: Vague descriptions
tool :complex_operation, description: "Does stuff"
```

## Performance Considerations

### 1. Lazy Loading

```ruby
class OptimizedToolset < DSPy::Tools::Toolset
  def initialize
    @expensive_resource = nil
  end
  
  private
  
  def expensive_resource
    @expensive_resource ||= create_expensive_resource
  end
  
  def create_expensive_resource
    # Expensive initialization
  end
end
```

### 2. Connection Pooling

```ruby
class DatabaseToolset < DSPy::Tools::Toolset
  def initialize(connection_string:, pool_size: 5)
    @connection_pool = ConnectionPool.new(size: pool_size) do
      establish_connection(connection_string)
    end
  end
  
  def query(sql:, params: {})
    @connection_pool.with do |connection|
      connection.execute(sql, params)
    end
  end
end
```

### 3. Caching

```ruby
class CachedToolset < DSPy::Tools::Toolset
  def initialize
    @cache = {}
  end
  
  def expensive_operation(data:)
    cache_key = generate_cache_key(data)
    
    @cache[cache_key] ||= perform_expensive_operation(data)
  end
  
  private
  
  def generate_cache_key(data)
    Digest::MD5.hexdigest(data.to_s)
  end
end
```

Custom toolsets allow you to extend agents with domain-specific capabilities by grouping related operations together. By following these patterns and best practices, you can build robust, secure, and performant toolsets that integrate with DSPy.rb's agent system.