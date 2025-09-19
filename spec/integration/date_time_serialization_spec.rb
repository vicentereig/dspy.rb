# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Date/DateTime serialization integration' do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  # Define test types based on the email timeline example
  class EmailType < T::Struct
    const :id, String
    const :subject, String
    const :from, String
    const :date, DateTime
    const :content, String
  end

  class EventSummary < T::Struct
    const :date, Date
    const :title, String
    const :description, String
    const :participants, T::Array[String]
    const :email_ids, T::Array[String]
    const :category, String
  end

  class PersonSummary < T::Struct
    const :email, String
    const :name, String
    const :interaction_count, Integer
    const :topics_discussed, T::Array[String]
  end

  class ActionItem < T::Struct
    const :description, String
    const :due_date, T.nilable(Date)
    const :assigned_to, T.nilable(String)
    const :status, String
    const :source_email_id, String
  end

  # Email timeline summary signature with Date fields
  class EmailTimelineSummarySignature < DSPy::Signature
    description "Generates a comprehensive summary of events from emails in a time period"

    input do
      const :start_date, Date
      const :end_date, Date
      const :emails, T::Array[EmailType]
      const :focus_areas, T::Array[String], default: ["meetings", "decisions", "projects", "personal"]
    end

    output do
      const :summary, String
      const :key_events, T::Array[EventSummary]
      const :important_people, T::Array[PersonSummary]
      const :projects_mentioned, T::Array[String]
      const :action_items, T::Array[ActionItem]
      const :timeline_highlights, T::Hash[String, T::Array[String]]
    end
  end

  # Simple signature for basic Date/DateTime testing
  class DateTimeTestSignature < DSPy::Signature
    description "Tests basic Date and DateTime handling"

    input do
      const :test_date, Date
      const :test_datetime, DateTime
      const :test_time, Time
      const :optional_date, T.nilable(Date), default: nil
    end

    output do
      const :parsed_date, Date
      const :parsed_datetime, DateTime
      const :parsed_time, Time
      const :formatted_date_string, String
      const :days_difference, Integer
    end
  end

  describe 'JSON Schema generation' do
    it 'generates correct schema for Date fields' do
      schema = EmailTimelineSummarySignature.input_json_schema
      
      expect(schema[:properties][:start_date]).to eq({
        type: "string",
        format: "date"
      })
      expect(schema[:properties][:end_date]).to eq({
        type: "string",
        format: "date"
      })
    end

    it 'generates correct schema for DateTime fields in nested structs' do
      schema = EmailTimelineSummarySignature.input_json_schema
      email_items_schema = schema[:properties][:emails][:items]
      
      expect(email_items_schema[:properties][:date]).to eq({
        type: "string",
        format: "date-time"
      })
    end

    it 'generates correct schema for nilable Date fields' do
      schema = DateTimeTestSignature.input_json_schema
      
      expect(schema[:properties][:optional_date]).to eq({
        type: ["string", "null"],
        format: "date"
      })
    end
  end

  describe 'Date/DateTime coercion' do
    let(:predictor) { DSPy::Predict.new(DateTimeTestSignature) }

    describe 'with valid date strings' do
      skip "Requires OpenAI API key" unless ENV['OPENAI_API_KEY']

      it 'handles ISO 8601 date formats' do
        VCR.use_cassette('integration/date_time_basic_coercion') do
          result = predictor.call(
            test_date: "2024-01-15",
            test_datetime: "2024-01-15T10:30:45Z",
            test_time: "2024-01-15T10:30:45+00:00"
          )

          # Verify input coercion worked
          expect(result.test_date).to be_a(Date)
          expect(result.test_date).to eq(Date.new(2024, 1, 15))
          
          expect(result.test_datetime).to be_a(DateTime)
          expect(result.test_time).to be_a(Time)
          expect(result.test_time.utc?).to be true

          # Verify LLM output coercion
          expect(result.parsed_date).to be_a(Date)
          expect(result.parsed_datetime).to be_a(DateTime)
          expect(result.parsed_time).to be_a(Time)
          expect(result.formatted_date_string).to be_a(String)
          expect(result.days_difference).to be_a(Integer)
        end
      end

      it 'handles various date formats from LLM output' do
        VCR.use_cassette('integration/date_time_format_flexibility') do
          result = predictor.call(
            test_date: Date.new(2024, 3, 15),
            test_datetime: DateTime.new(2024, 3, 15, 14, 30, 0),
            test_time: Time.new(2024, 3, 15, 14, 30, 0, "+00:00")
          )

          # The LLM might return dates in different string formats
          # Our coercion should handle them gracefully
          expect(result.parsed_date).to be_a(Date)
          expect(result.parsed_datetime).to be_a(DateTime)
          expect(result.parsed_time).to be_a(Time)
        end
      end
    end

    describe 'with nilable dates' do
      it 'handles nil values correctly' do
        # Test direct coercion without LLM - create a test helper class
        test_helper = Class.new do
          include DSPy::Mixins::TypeCoercion
        end.new
        
        expect(test_helper.send(:coerce_date_value, nil)).to be_nil
        expect(test_helper.send(:coerce_date_value, "")).to be_nil
        expect(test_helper.send(:coerce_date_value, "   ")).to be_nil
        
        expect(test_helper.send(:coerce_datetime_value, nil)).to be_nil
        expect(test_helper.send(:coerce_time_value, nil)).to be_nil
      end

      it 'handles invalid date strings gracefully' do
        test_helper = Class.new do
          include DSPy::Mixins::TypeCoercion
        end.new
        
        expect(test_helper.send(:coerce_date_value, "invalid-date")).to be_nil
        expect(test_helper.send(:coerce_date_value, "2024-13-45")).to be_nil
        expect(test_helper.send(:coerce_datetime_value, "not-a-datetime")).to be_nil
        expect(test_helper.send(:coerce_time_value, "bad-time")).to be_nil
      end
    end
  end

  describe 'Complex email timeline scenario' do
    skip "Requires OpenAI API key" unless ENV['OPENAI_API_KEY']

    let(:predictor) { DSPy::Predict.new(EmailTimelineSummarySignature) }
    
    let(:sample_emails) do
      [
        EmailType.new(
          id: "email-1",
          subject: "Project Kickoff Meeting",
          from: "alice@example.com",
          date: DateTime.new(2024, 1, 15, 9, 0, 0),
          content: "Let's schedule the project kickoff for next Monday at 2 PM."
        ),
        EmailType.new(
          id: "email-2", 
          subject: "Budget Approval Required",
          from: "bob@example.com",
          date: DateTime.new(2024, 1, 17, 11, 30, 0),
          content: "The budget needs approval by January 20th for Q1 planning."
        )
      ]
    end

    it 'processes complex timeline with dates in nested structures' do
      VCR.use_cassette('integration/date_time_email_timeline') do
        result = predictor.call(
          start_date: Date.new(2024, 1, 1),
          end_date: Date.new(2024, 1, 31),
          emails: sample_emails
        )

        # Verify input dates were properly serialized
        expect(result.start_date).to eq(Date.new(2024, 1, 1))
        expect(result.end_date).to eq(Date.new(2024, 1, 31))
        expect(result.emails).to be_an(Array)
        expect(result.emails.first.date).to be_a(DateTime)

        # Verify LLM output contains properly typed dates
        expect(result.summary).to be_a(String)
        expect(result.key_events).to be_an(Array)
        
        if result.key_events.any?
          result.key_events.each do |event|
            expect(event).to be_a(EventSummary)
            expect(event.date).to be_a(Date)
            expect(event.title).to be_a(String)
            expect(event.participants).to be_an(Array)
          end
        end

        if result.action_items.any?
          result.action_items.each do |item|
            expect(item).to be_a(ActionItem)
            expect(item.description).to be_a(String)
            # due_date is nilable, so it can be Date or nil
            expect([Date, NilClass]).to include(item.due_date.class)
          end
        end
      end
    end

    it 'handles timezone conversions properly' do
      # Create emails with different timezones
      utc_time = Time.new(2024, 1, 15, 15, 0, 0, "+00:00")
      pst_time = Time.new(2024, 1, 15, 7, 0, 0, "-08:00")  # Same as UTC time
      
      emails_with_tz = [
        EmailType.new(
          id: "email-utc",
          subject: "UTC Meeting",
          from: "utc@example.com", 
          date: utc_time.to_datetime,
          content: "Meeting scheduled in UTC timezone."
        ),
        EmailType.new(
          id: "email-pst",
          subject: "PST Meeting", 
          from: "pst@example.com",
          date: pst_time.to_datetime,
          content: "Meeting scheduled in PST timezone."
        )
      ]

      VCR.use_cassette('integration/date_time_timezone_handling') do
        result = predictor.call(
          start_date: Date.new(2024, 1, 1),
          end_date: Date.new(2024, 1, 31),
          emails: emails_with_tz
        )

        # Both emails should be present as they're the same moment in time
        expect(result.emails.length).to eq(2)
        
        # Verify timezone information is preserved in DateTime objects
        utc_email = result.emails.find { |e| e.id == "email-utc" }
        pst_email = result.emails.find { |e| e.id == "email-pst" }
        
        expect(utc_email.date).to be_a(DateTime)
        expect(pst_email.date).to be_a(DateTime)
        
        # The underlying time should be equivalent even if timezone differs
        expect(utc_email.date.to_time.to_i).to eq(pst_email.date.to_time.to_i)
      end
    end
  end

  describe 'Edge cases and error handling' do
    it 'handles leap years correctly' do
      test_helper = Class.new do
        include DSPy::Mixins::TypeCoercion
      end.new
      
      leap_date = test_helper.send(:coerce_date_value, "2024-02-29")  # 2024 is a leap year
      expect(leap_date).to eq(Date.new(2024, 2, 29))
      
      non_leap_date = test_helper.send(:coerce_date_value, "2023-02-29")  # 2023 is not a leap year
      expect(non_leap_date).to be_nil  # Should gracefully handle invalid date
    end

    it 'handles various ISO 8601 datetime formats' do
      test_helper = Class.new do
        include DSPy::Mixins::TypeCoercion
      end.new
      
      formats = [
        "2024-01-15T10:30:45Z",
        "2024-01-15T10:30:45+00:00", 
        "2024-01-15T10:30:45-05:00",
        "2024-01-15 10:30:45",
        "2024-01-15T10:30:45.123Z"
      ]
      
      formats.each do |format|
        result = test_helper.send(:coerce_datetime_value, format)
        expect(result).to be_a(DateTime), "Failed to parse format: #{format}"
      end
    end

    it 'preserves existing Date/DateTime objects without modification' do
      test_helper = Class.new do
        include DSPy::Mixins::TypeCoercion
      end.new
      
      original_date = Date.new(2024, 1, 15)
      original_datetime = DateTime.new(2024, 1, 15, 10, 30, 45)
      original_time = Time.new(2024, 1, 15, 10, 30, 45)
      
      expect(test_helper.send(:coerce_date_value, original_date)).to equal(original_date)
      expect(test_helper.send(:coerce_datetime_value, original_datetime)).to equal(original_datetime)
      expect(test_helper.send(:coerce_time_value, original_time)).to equal(original_time)
    end
  end
end