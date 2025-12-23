# frozen_string_literal: true

require 'sorbet-runtime'
require 'net/http'
require 'json'
require 'base64'

module DSPy
  class Observability
    module Adapters
      module Langfuse
        # Async exporter for sending scores to Langfuse REST API
        # Uses a background thread to avoid blocking the main application
        class ScoresExporter
          extend T::Sig

          DEFAULT_HOST = 'https://cloud.langfuse.com'
          SCORES_ENDPOINT = '/api/public/scores'
          DEFAULT_MAX_RETRIES = 3
          DEFAULT_TIMEOUT = 10

          attr_reader :host

          sig do
            params(
              public_key: String,
              secret_key: String,
              host: String,
              max_retries: Integer,
              timeout: Integer
            ).void
          end
          def initialize(
            public_key:,
            secret_key:,
            host: DEFAULT_HOST,
            max_retries: DEFAULT_MAX_RETRIES,
            timeout: DEFAULT_TIMEOUT
          )
            @public_key = public_key
            @secret_key = secret_key
            @host = host.chomp('/')
            @max_retries = max_retries
            @timeout = timeout
            @queue = Thread::Queue.new
            @running = false
            @worker_thread = nil
            @subscription_id = nil
            @mutex = Mutex.new
          end

          # Factory method that creates, starts, and subscribes to events
          sig do
            params(
              public_key: String,
              secret_key: String,
              host: String,
              max_retries: Integer,
              timeout: Integer
            ).returns(ScoresExporter)
          end
          def self.configure(
            public_key:,
            secret_key:,
            host: DEFAULT_HOST,
            max_retries: DEFAULT_MAX_RETRIES,
            timeout: DEFAULT_TIMEOUT
          )
            exporter = new(
              public_key: public_key,
              secret_key: secret_key,
              host: host,
              max_retries: max_retries,
              timeout: timeout
            )
            exporter.start
            exporter.subscribe_to_events
            exporter
          end

          sig { void }
          def start
            @mutex.synchronize do
              return if @running

              @running = true
              @worker_thread = Thread.new { process_queue }
            end
          end

          sig { returns(T::Boolean) }
          def running?
            @mutex.synchronize { @running }
          end

          sig { params(score_event: DSPy::Scores::ScoreEvent).void }
          def export(score_event)
            return unless running?

            @queue.push(score_event)
          end

          sig { returns(Integer) }
          def queue_size
            @queue.size
          end

          sig { void }
          def subscribe_to_events
            @subscription_id = DSPy.events.subscribe('score.create') do |_name, attrs|
              # Reconstruct ScoreEvent from event attributes
              score_event = DSPy::Scores::ScoreEvent.new(
                id: attrs[:score_id],
                name: attrs[:score_name],
                value: attrs[:score_value],
                data_type: DSPy::Scores::DataType.deserialize(attrs[:score_data_type]),
                comment: attrs[:score_comment],
                trace_id: attrs[:trace_id],
                observation_id: attrs[:observation_id]
              )
              export(score_event)
            end
          end

          sig { params(timeout: Integer).void }
          def shutdown(timeout: 5)
            @mutex.synchronize do
              return unless @running

              @running = false

              # Unsubscribe from events
              DSPy.events.unsubscribe(@subscription_id) if @subscription_id
              @subscription_id = nil

              # Signal worker to stop
              @queue.push(:stop)
            end

            # Wait for worker thread to finish
            @worker_thread&.join(timeout)
          end

          private

          sig { void }
          def process_queue
            while running? || !@queue.empty?
              item = @queue.pop

              break if item == :stop

              begin
                send_with_retry(item)
              rescue StandardError => e
                DSPy.log('scores.export_error', error: e.message, score_name: item.name)
              end
            end
          end

          sig { params(score_event: DSPy::Scores::ScoreEvent).void }
          def send_with_retry(score_event)
            retries = 0

            begin
              send_to_langfuse(score_event)
            rescue StandardError => e
              retries += 1
              if retries <= @max_retries
                sleep(exponential_backoff(retries))
                retry
              else
                raise e
              end
            end
          end

          sig { params(attempt: Integer).returns(Float) }
          def exponential_backoff(attempt)
            # 0.1s, 0.2s, 0.4s, 0.8s... with jitter
            base_delay = 0.1 * (2 ** (attempt - 1))
            base_delay + rand * 0.1
          end

          sig { params(score_event: DSPy::Scores::ScoreEvent).void }
          def send_to_langfuse(score_event)
            uri = URI("#{@host}#{SCORES_ENDPOINT}")
            payload = build_payload(score_event)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.open_timeout = @timeout
            http.read_timeout = @timeout

            request = Net::HTTP::Post.new(uri.path)
            request['Content-Type'] = 'application/json'
            request['Authorization'] = "Basic #{auth_token}"
            request.body = JSON.generate(payload)

            response = http.request(request)

            unless response.is_a?(Net::HTTPSuccess)
              raise "Langfuse API error: #{response.code} - #{response.body}"
            end

            DSPy.log('scores.exported', score_name: score_event.name, score_id: score_event.id)
          end

          sig { params(score_event: DSPy::Scores::ScoreEvent).returns(T::Hash[Symbol, T.untyped]) }
          def build_payload(score_event)
            score_event.to_langfuse_payload
          end

          sig { returns(String) }
          def auth_token
            Base64.strict_encode64("#{@public_key}:#{@secret_key}")
          end
        end
      end
    end
  end
end
