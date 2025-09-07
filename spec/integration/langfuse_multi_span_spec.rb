# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Langfuse Multi-Span Export", type: :integration do
  before(:all) do
    # Skip tests when Langfuse credentials aren't available
    skip 'Requires LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY' unless 
      ENV['LANGFUSE_PUBLIC_KEY'] && ENV['LANGFUSE_SECRET_KEY']
    
    # Configure observability with real Langfuse credentials
    DSPy::Observability.configure!
  end
  
  after(:all) do
    # Clean up observability state
    DSPy::Observability.reset!
  end
  
  it "exports multiple spans to Langfuse in batches" do
    expect(DSPy::Observability.enabled?).to be true
    
    captured_logs = []
    original_log_method = DSPy.method(:log)
    
    # Capture diagnostic logs
    allow(DSPy).to receive(:log) do |event, **attributes|
      if event.to_s.start_with?('observability.')
        captured_logs << { event: event, attributes: attributes }
      end
      original_log_method.call(event, **attributes)
    end
    
    # Create multiple spans that should batch together
    span_count = 15
    results = []
    
    span_count.times do |i|
      result = DSPy::Context.with_span(
        operation: "test.batch_span_#{i}",
        test_index: i,
        test_batch: "multi_span_test"
      ) do |span|
        # Simulate some work
        sleep(0.01)
        "result_#{i}"
      end
      results << result
    end
    
    # Force flush to export all spans
    DSPy::Observability.flush!
    
    # Wait for async export to complete
    sleep(2)
    
    # Verify all spans were created
    expect(results).to have_attributes(size: span_count)
    results.each_with_index { |result, i| expect(result).to eq("result_#{i}") }
    
    # Analyze diagnostic logs
    queue_logs = captured_logs.select { |log| log[:event] == 'observability.span_queued' }
    export_logs = captured_logs.select { |log| log[:event] == 'observability.export_attempt' }
    success_logs = captured_logs.select { |log| log[:event] == 'observability.export_success' }
    
    expect(queue_logs).to have_attributes(size: span_count)
    expect(export_logs.size).to be > 0
    expect(success_logs.size).to be > 0
    
    # Should see multiple spans exported in batches
    total_exported = success_logs.sum { |log| log[:attributes][:spans_count] }
    expect(total_exported).to be >= span_count
    
    puts "Created #{span_count} spans"
    puts "Export attempts: #{export_logs.size}"
    puts "Successful exports: #{success_logs.size}"
    puts "Total spans exported: #{total_exported}"
  end
  
  it "handles nested spans correctly" do
    expect(DSPy::Observability.enabled?).to be true
    
    captured_logs = []
    original_log_method = DSPy.method(:log)
    
    allow(DSPy).to receive(:log) do |event, **attributes|
      if event.to_s.start_with?('observability.')
        captured_logs << { event: event, attributes: attributes }
      end
      original_log_method.call(event, **attributes)
    end
    
    result = DSPy::Context.with_span(
      operation: "test.parent_span",
      level: "parent"
    ) do |parent_span|
      child_results = []
      
      3.times do |i|
        child_result = DSPy::Context.with_span(
          operation: "test.child_span_#{i}",
          level: "child",
          parent_index: i
        ) do |child_span|
          sleep(0.01)
          "child_#{i}"
        end
        child_results << child_result
      end
      
      { parent: "parent_result", children: child_results }
    end
    
    DSPy::Observability.flush!
    sleep(2)
    
    expect(result[:parent]).to eq("parent_result")
    expect(result[:children]).to eq(["child_0", "child_1", "child_2"])
    
    # Should have 4 spans total (1 parent + 3 children)
    queue_logs = captured_logs.select { |log| log[:event] == 'observability.span_queued' }
    expect(queue_logs.size).to eq(4)
  end
end