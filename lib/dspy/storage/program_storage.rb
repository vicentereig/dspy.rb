# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'
require 'fileutils'
require 'digest'

module DSPy
  module Storage
    # Storage system for saving and loading optimized DSPy programs
    # Handles serialization of optimization results, program state, and history tracking
    class ProgramStorage
      extend T::Sig

      # Represents a saved program with metadata
      class SavedProgram
        extend T::Sig

        sig { returns(T.untyped) }
        attr_reader :program

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :optimization_result

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :metadata

        sig { returns(String) }
        attr_reader :program_id

        sig { returns(Time) }
        attr_reader :saved_at

        sig do
          params(
            program: T.untyped,
            optimization_result: T::Hash[Symbol, T.untyped],
            metadata: T::Hash[Symbol, T.untyped],
            program_id: T.nilable(String),
            saved_at: T.nilable(Time)
          ).void
        end
        def initialize(program:, optimization_result:, metadata: {}, program_id: nil, saved_at: nil)
          @program = program
          @optimization_result = optimization_result
          dspy_version = begin
            DSPy::VERSION
          rescue
            "unknown"
          end
          
          @metadata = metadata.merge({
            dspy_version: dspy_version,
            ruby_version: RUBY_VERSION,
            saved_with: "DSPy::Storage::ProgramStorage"
          })
          @program_id = program_id || generate_program_id
          @saved_at = saved_at || Time.now
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            program_id: @program_id,
            saved_at: @saved_at.iso8601,
            program_data: serialize_program(@program),
            optimization_result: @optimization_result,
            metadata: @metadata
          }
        end

        sig { params(data: T::Hash[Symbol, T.untyped]).returns(SavedProgram) }
        def self.from_h(data)
          new(
            program: deserialize_program(data[:program_data]),
            optimization_result: data[:optimization_result],
            metadata: data[:metadata] || {},
            program_id: data[:program_id],
            saved_at: Time.parse(data[:saved_at])
          )
        end

        private

        sig { returns(String) }
        def generate_program_id
          content = "#{@optimization_result[:best_score_value]}_#{@metadata.hash}_#{Time.now.to_f}"
          Digest::SHA256.hexdigest(content)[0, 16]
        end

        sig { params(program: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_program(program)
          # Basic serialization
          if program.is_a?(Hash)
            # Already serialized - return as-is to preserve state
            program
          else
            # Real program object - serialize it
            {
              class_name: program.class.name,
              state: extract_program_state(program)
            }
          end
        end

        sig { params(data: T.untyped).returns(T.untyped) }
        def self.deserialize_program(data)
          # Ensure data is a Hash
          unless data.is_a?(Hash)
            raise ArgumentError, "Expected Hash for program data, got #{data.class.name}"
          end
          
          # Get class name from the serialized data
          class_name = data[:class_name]
          raise ArgumentError, "Missing class_name in serialized data" unless class_name
          
          # Get the class constant
          program_class = Object.const_get(class_name)
          
          # Use the class's from_h method
          unless program_class.respond_to?(:from_h)
            raise ArgumentError, "Class #{class_name} does not support deserialization (missing from_h method)"
          end
          
          program_class.from_h(data)
        end

        sig { params(program: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def extract_program_state(program)
          state = {}
          
          # Extract common program properties
          if program.respond_to?(:signature_class)
            state[:signature_class] = program.signature_class&.name
          end
          
          if program.respond_to?(:prompt) && program.prompt.respond_to?(:instruction)
            state[:instruction] = program.prompt.instruction
          end
          
          if program.respond_to?(:few_shot_examples)
            state[:few_shot_examples] = program.few_shot_examples
          end
          
          state
        end
      end

      sig { returns(String) }
      attr_reader :storage_path

      sig { returns(T::Boolean) }
      attr_reader :create_directories

      sig do
        params(
          storage_path: String,
          create_directories: T::Boolean
        ).void
      end
      def initialize(storage_path: "./dspy_storage", create_directories: true)
        @storage_path = File.expand_path(storage_path)
        @create_directories = create_directories
        
        setup_storage_directory if @create_directories
      end

      # Save an optimized program with its optimization results
      sig do
        params(
          program: T.untyped,
          optimization_result: T.untyped,
          program_id: T.nilable(String),
          metadata: T::Hash[Symbol, T.untyped]
        ).returns(SavedProgram)
      end
      def save_program(program, optimization_result, program_id: nil, metadata: {})
        emit_save_start_event(program_id)
        
        begin
          # Convert optimization result to hash if it's an object
          result_hash = optimization_result.respond_to?(:to_h) ? optimization_result.to_h : optimization_result
          
          saved_program = SavedProgram.new(
            program: program,
            optimization_result: result_hash,
            metadata: metadata,
            program_id: program_id
          )
          
          # Write to file
          file_path = program_file_path(saved_program.program_id)
          File.write(file_path, JSON.pretty_generate(saved_program.to_h))
          
          # Update history
          update_history(saved_program)
          
          emit_save_complete_event(saved_program)
          saved_program
          
        rescue => error
          emit_save_error_event(program_id, error)
          raise
        end
      end

      # Load a program by its ID
      sig { params(program_id: String).returns(T.nilable(SavedProgram)) }
      def load_program(program_id)
        emit_load_start_event(program_id)
        
        begin
          file_path = program_file_path(program_id)
          
          unless File.exist?(file_path)
            emit_load_error_event(program_id, "Program not found: #{program_id}")
            return nil
          end
          
          data = JSON.parse(File.read(file_path), symbolize_names: true)
          saved_program = SavedProgram.from_h(data)
          
          emit_load_complete_event(saved_program)
          saved_program
          
        rescue => error
          emit_load_error_event(program_id, error)
          nil
        end
      end

      # List all saved programs
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def list_programs
        history_path = File.join(@storage_path, "history.json")
        return [] unless File.exist?(history_path)
        
        history_data = JSON.parse(File.read(history_path), symbolize_names: true)
        history_data[:programs] || []
      end

      # Get program history with performance metrics
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def get_history
        history_path = File.join(@storage_path, "history.json")
        return { programs: [], summary: {} } unless File.exist?(history_path)
        
        JSON.parse(File.read(history_path), symbolize_names: true)
      end

      # Delete a saved program
      sig { params(program_id: String).returns(T::Boolean) }
      def delete_program(program_id)
        file_path = program_file_path(program_id)
        
        if File.exist?(file_path)
          File.delete(file_path)
          remove_from_history(program_id)
          emit_delete_event(program_id)
          true
        else
          false
        end
      end

      # Export multiple programs to a single file
      sig { params(program_ids: T::Array[String], export_path: String).void }
      def export_programs(program_ids, export_path)
        programs = program_ids.map { |id| load_program(id) }.compact
        
        dspy_version = begin
          DSPy::VERSION
        rescue
          "unknown"
        end
        
        export_data = {
          exported_at: Time.now.iso8601,
          dspy_version: dspy_version,
          programs: programs.map(&:to_h)
        }
        
        File.write(export_path, JSON.pretty_generate(export_data))
        emit_export_event(export_path, programs.size)
      end

      # Import programs from an exported file
      sig { params(import_path: String).returns(T::Array[SavedProgram]) }
      def import_programs(import_path)
        data = JSON.parse(File.read(import_path), symbolize_names: true)
        imported = []
        
        data[:programs].each do |program_data|
          saved_program = SavedProgram.from_h(program_data)
          
          # Save with new timestamp but preserve original ID
          file_path = program_file_path(saved_program.program_id)
          File.write(file_path, JSON.pretty_generate(saved_program.to_h))
          
          update_history(saved_program)
          imported << saved_program
        end
        
        emit_import_event(import_path, imported.size)
        imported
      end

      private

      sig { void }
      def setup_storage_directory
        FileUtils.mkdir_p(@storage_path) unless Dir.exist?(@storage_path)
        
        # Create programs subdirectory
        programs_dir = File.join(@storage_path, "programs")
        FileUtils.mkdir_p(programs_dir) unless Dir.exist?(programs_dir)
      end

      sig { params(program_id: String).returns(String) }
      def program_file_path(program_id)
        File.join(@storage_path, "programs", "#{program_id}.json")
      end

      sig { params(saved_program: SavedProgram).void }
      def update_history(saved_program)
        history_path = File.join(@storage_path, "history.json")
        
        history = if File.exist?(history_path)
          JSON.parse(File.read(history_path), symbolize_names: true)
        else
          { programs: [], summary: { total_programs: 0, avg_score: 0.0 } }
        end
        
        # Extract signature class name from program object
        unless saved_program.program.respond_to?(:signature_class)
          raise ArgumentError, "Program #{saved_program.program.class.name} does not respond to signature_class method"
        end
        
        signature_class_name = saved_program.program.signature_class.name
        
        if signature_class_name.nil? || signature_class_name.empty?
          raise(
            "Program #{saved_program.program.class.name} has a signature class that does not provide a name.\n" \
            "Ensure the signature class responds to #name or that signature_class_name is stored in program state."
          )
        end
        
        # Add or update program entry
        program_entry = {
          program_id: saved_program.program_id,
          saved_at: saved_program.saved_at.iso8601,
          best_score: saved_program.optimization_result[:best_score_value],
          score_name: saved_program.optimization_result[:best_score_name],
          optimizer: saved_program.optimization_result[:metadata]&.dig(:optimizer),
          signature_class: signature_class_name,
          metadata: saved_program.metadata
        }
        
        # Remove existing entry if updating
        history[:programs].reject! { |p| p[:program_id] == saved_program.program_id }
        history[:programs] << program_entry
        
        # Update summary
        scores = history[:programs].map { |p| p[:best_score] }.compact
        history[:summary] = {
          total_programs: history[:programs].size,
          avg_score: scores.empty? ? 0.0 : scores.sum.to_f / scores.size,
          latest_save: saved_program.saved_at.iso8601
        }
        
        File.write(history_path, JSON.pretty_generate(history))
      end

      sig { params(program_id: String).void }
      def remove_from_history(program_id)
        history_path = File.join(@storage_path, "history.json")
        return unless File.exist?(history_path)
        
        history = JSON.parse(File.read(history_path), symbolize_names: true)
        history[:programs].reject! { |p| p[:program_id] == program_id }
        
        # Recalculate summary
        scores = history[:programs].map { |p| p[:best_score] }.compact
        history[:summary] = {
          total_programs: history[:programs].size,
          avg_score: scores.empty? ? 0.0 : scores.sum.to_f / scores.size
        }
        
        File.write(history_path, JSON.pretty_generate(history))
      end

      # Event emission methods
      sig { params(program_id: T.nilable(String)).void }
      def emit_save_start_event(program_id)
        DSPy.log('storage.save_start', **{
          'storage.program_id' => program_id,
          'storage.path' => @storage_path
        })
      end

      sig { params(saved_program: SavedProgram).void }
      def emit_save_complete_event(saved_program)
        DSPy.log('storage.save_complete', **{
          'storage.program_id' => saved_program.program_id,
          'storage.best_score' => saved_program.optimization_result[:best_score_value],
          'storage.file_size' => File.size(program_file_path(saved_program.program_id))
        })
      end

      sig { params(program_id: T.nilable(String), error: Exception).void }
      def emit_save_error_event(program_id, error)
        DSPy.log('storage.save_error', **{
          'storage.program_id' => program_id,
          'storage.error' => error.message,
          'storage.error_class' => error.class.name
        })
      end

      sig { params(program_id: String).void }
      def emit_load_start_event(program_id)
        DSPy.log('storage.load_start', **{
          'storage.program_id' => program_id
        })
      end

      sig { params(saved_program: SavedProgram).void }
      def emit_load_complete_event(saved_program)
        DSPy.log('storage.load_complete', **{
          'storage.program_id' => saved_program.program_id,
          'storage.saved_at' => saved_program.saved_at.iso8601,
          'storage.age_hours' => ((Time.now - saved_program.saved_at) / 3600).round(2)
        })
      end

      sig { params(program_id: String, error: T.any(String, Exception)).void }
      def emit_load_error_event(program_id, error)
        error_message = error.is_a?(Exception) ? error.message : error.to_s
        DSPy.log('storage.load_error', **{
          'storage.program_id' => program_id,
          'storage.error' => error_message
        })
      end

      sig { params(program_id: String).void }
      def emit_delete_event(program_id)
        DSPy.log('storage.delete', **{
          'storage.program_id' => program_id
        })
      end

      sig { params(export_path: String, program_count: Integer).void }
      def emit_export_event(export_path, program_count)
        DSPy.log('storage.export', **{
          'storage.export_path' => export_path,
          'storage.program_count' => program_count
        })
      end

      sig { params(import_path: String, program_count: Integer).void }
      def emit_import_event(import_path, program_count)
        DSPy.log('storage.import', **{
          'storage.import_path' => import_path,
          'storage.program_count' => program_count
        })
      end
    end
  end
end