# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'program_storage'

module DSPy
  module Storage
    # High-level storage manager that integrates with the teleprompter system
    # Provides easy saving/loading of optimization results
    class StorageManager
      extend T::Sig

      # Configuration for storage behavior
      class StorageConfig
        extend T::Sig

        sig { returns(String) }
        attr_accessor :storage_path

        sig { returns(T::Boolean) }
        attr_accessor :auto_save

        sig { returns(T::Boolean) }
        attr_accessor :save_intermediate_results

        sig { returns(Integer) }
        attr_accessor :max_stored_programs

        sig { returns(T::Boolean) }
        attr_accessor :compress_old_programs

        sig { void }
        def initialize
          @storage_path = "./dspy_storage"
          @auto_save = true
          @save_intermediate_results = false
          @max_stored_programs = 100
          @compress_old_programs = false
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            storage_path: @storage_path,
            auto_save: @auto_save,
            save_intermediate_results: @save_intermediate_results,
            max_stored_programs: @max_stored_programs,
            compress_old_programs: @compress_old_programs
          }
        end
      end

      sig { returns(StorageConfig) }
      attr_reader :config

      sig { returns(ProgramStorage) }
      attr_reader :storage

      sig { params(config: T.nilable(StorageConfig)).void }
      def initialize(config: nil)
        @config = config || StorageConfig.new
        @storage = ProgramStorage.new(
          storage_path: @config.storage_path,
          create_directories: true
        )
      end

      # Save optimization result from teleprompter
      sig do
        params(
          optimization_result: T.untyped,
          tags: T::Array[String],
          description: T.nilable(String),
          metadata: T::Hash[Symbol, T.untyped]
        ).returns(T.nilable(ProgramStorage::SavedProgram))
      end
      def save_optimization_result(optimization_result, tags: [], description: nil, metadata: {})
        return nil unless @config.auto_save
        
        program = optimization_result.respond_to?(:optimized_program) ? 
                 optimization_result.optimized_program : nil
        return nil unless program

        enhanced_metadata = metadata.merge({
          tags: tags,
          description: description,
          optimizer_class: optimization_result.class.name,
          saved_by: "StorageManager",
          optimization_timestamp: optimization_result.respond_to?(:metadata) ? 
                                 optimization_result.metadata[:optimization_timestamp] : nil
        })

        @storage.save_program(
          program,
          optimization_result,
          metadata: enhanced_metadata
        )
      end

      # Find programs by criteria
      sig do
        params(
          optimizer: T.nilable(String),
          min_score: T.nilable(Float),
          max_age_days: T.nilable(Integer),
          tags: T::Array[String],
          signature_class: T.nilable(String)
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def find_programs(optimizer: nil, min_score: nil, max_age_days: nil, tags: [], signature_class: nil)
        programs = @storage.list_programs
        
        programs.select do |program|
          # Filter by optimizer
          next false if optimizer && program[:optimizer] != optimizer
          
          # Filter by minimum score
          next false if min_score && (program[:best_score] || 0) < min_score
          
          # Filter by age
          if max_age_days
            saved_at = Time.parse(program[:saved_at])
            age_days = (Time.now - saved_at) / (24 * 60 * 60)
            next false if age_days > max_age_days
          end
          
          # Filter by signature class
          next false if signature_class && program[:signature_class] != signature_class
          
          # Filter by tags (if any tags specified, program must have at least one)
          if tags.any?
            program_tags = program.dig(:metadata, :tags) || []
            next false unless (tags & program_tags).any?
          end
          
          true
        end
      end

      # Get the best performing program for a signature class
      sig { params(signature_class: String).returns(T.nilable(ProgramStorage::SavedProgram)) }
      def get_best_program(signature_class)
        matching_programs = find_programs(signature_class: signature_class)
        return nil if matching_programs.empty?
        
        best_program_info = matching_programs.max_by { |p| p[:best_score] || 0 }
        @storage.load_program(best_program_info[:program_id])
      end

      # Create a checkpoint from current optimization state
      sig do
        params(
          optimization_result: T.untyped,
          checkpoint_name: String,
          metadata: T::Hash[Symbol, T.untyped]
        ).returns(T.nilable(ProgramStorage::SavedProgram))
      end
      def create_checkpoint(optimization_result, checkpoint_name, metadata: {})
        enhanced_metadata = metadata.merge({
          checkpoint: true,
          checkpoint_name: checkpoint_name,
          created_at: Time.now.iso8601
        })

        save_optimization_result(
          optimization_result,
          tags: ["checkpoint"],
          description: "Checkpoint: #{checkpoint_name}",
          metadata: enhanced_metadata
        )
      end

      # Restore from a checkpoint
      sig { params(checkpoint_name: String).returns(T.nilable(ProgramStorage::SavedProgram)) }
      def restore_checkpoint(checkpoint_name)
        programs = find_programs(tags: ["checkpoint"])
        checkpoint = programs.find do |p| 
          # Check both top-level and nested metadata
          p[:checkpoint_name] == checkpoint_name || 
          p.dig(:metadata, :checkpoint_name) == checkpoint_name
        end
        
        return nil unless checkpoint
        @storage.load_program(checkpoint[:program_id])
      end

      # Get optimization history and trends
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def get_optimization_history
        history = @storage.get_history
        
        # Calculate trends
        programs = history[:programs] || []
        return history if programs.empty?
        
        # Group by optimizer
        by_optimizer = programs.group_by { |p| p[:optimizer] }
        optimizer_stats = by_optimizer.transform_values do |progs|
          scores = progs.map { |p| p[:best_score] }.compact
          {
            count: progs.size,
            avg_score: scores.sum.to_f / scores.size,
            best_score: scores.max,
            latest: progs.max_by { |p| Time.parse(p[:saved_at]) }
          }
        end
        
        # Calculate improvement trends
        sorted_programs = programs.sort_by { |p| Time.parse(p[:saved_at]) }
        recent_programs = sorted_programs.last(10)
        older_programs = sorted_programs.first([sorted_programs.size - 10, 1].max)
        
        recent_avg = recent_programs.map { |p| p[:best_score] }.compact.sum.to_f / recent_programs.size
        older_avg = older_programs.map { |p| p[:best_score] }.compact.sum.to_f / older_programs.size
        improvement_trend = older_avg > 0 ? ((recent_avg - older_avg) / older_avg * 100).round(2) : 0

        history.merge({
          optimizer_stats: optimizer_stats,
          trends: {
            improvement_percentage: improvement_trend,
            recent_avg_score: recent_avg.round(4),
            older_avg_score: older_avg.round(4)
          }
        })
      end

      # Clean up old programs based on configuration
      sig { returns(Integer) }
      def cleanup_old_programs
        return 0 unless @config.max_stored_programs > 0
        
        programs = @storage.list_programs
        return 0 if programs.size <= @config.max_stored_programs
        
        # Sort by score (keep best) and recency (keep recent)
        sorted_programs = programs.sort_by do |p|
          score_rank = p[:best_score] || 0
          time_rank = Time.parse(p[:saved_at]).to_f / 1_000_000 # Convert to smaller number
          
          # Weighted combination: 70% score, 30% recency
          -(score_rank * 0.7 + time_rank * 0.3)
        end
        
        programs_to_delete = sorted_programs.drop(@config.max_stored_programs)
        deleted_count = 0
        
        programs_to_delete.each do |program|
          if @storage.delete_program(program[:program_id])
            deleted_count += 1
          end
        end
        
        DSPy.log('storage.cleanup', **{
          'storage.deleted_count' => deleted_count,
          'storage.remaining_count' => @config.max_stored_programs
        })
        
        deleted_count
      end

      # Compare two programs
      sig do
        params(
          program_id_1: String,
          program_id_2: String
        ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def compare_programs(program_id_1, program_id_2)
        program1 = @storage.load_program(program_id_1)
        program2 = @storage.load_program(program_id_2)
        
        return nil unless program1 && program2
        
        {
          program_1: {
            id: program1.program_id,
            score: program1.optimization_result[:best_score_value],
            optimizer: program1.optimization_result[:metadata]&.dig(:optimizer),
            saved_at: program1.saved_at.iso8601
          },
          program_2: {
            id: program2.program_id,
            score: program2.optimization_result[:best_score_value],
            optimizer: program2.optimization_result[:metadata]&.dig(:optimizer),
            saved_at: program2.saved_at.iso8601
          },
          comparison: {
            score_difference: (program1.optimization_result[:best_score_value] || 0) - 
                            (program2.optimization_result[:best_score_value] || 0),
            better_program: (program1.optimization_result[:best_score_value] || 0) > 
                          (program2.optimization_result[:best_score_value] || 0) ? 
                          program_id_1 : program_id_2,
            age_difference_hours: ((program1.saved_at - program2.saved_at) / 3600).round(2)
          }
        }
      end

      # Global storage instance
      @@instance = T.let(nil, T.nilable(StorageManager))

      # Get global storage instance
      sig { returns(StorageManager) }
      def self.instance
        @@instance ||= new
      end

      # Configure global storage
      sig { params(config: StorageConfig).void }
      def self.configure(config)
        @@instance = new(config: config)
      end

      # Shorthand methods for common operations
      sig { params(optimization_result: T.untyped, metadata: T::Hash[Symbol, T.untyped]).returns(T.nilable(ProgramStorage::SavedProgram)) }
      def self.save(optimization_result, metadata: {})
        instance.save_optimization_result(optimization_result, metadata: metadata)
      end

      sig { params(program_id: String).returns(T.nilable(ProgramStorage::SavedProgram)) }
      def self.load(program_id)
        instance.storage.load_program(program_id)
      end

      sig { params(signature_class: String).returns(T.nilable(ProgramStorage::SavedProgram)) }
      def self.best(signature_class)
        instance.get_best_program(signature_class)
      end
    end
  end
end