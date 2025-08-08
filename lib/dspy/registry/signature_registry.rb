# frozen_string_literal: true

require 'sorbet-runtime'
require 'yaml'
require 'fileutils'
require 'digest'

module DSPy
  module Registry
    # Registry for managing signature versions and deployments
    # Provides version control, rollback capabilities, and deployment tracking
    class SignatureRegistry
      extend T::Sig

      # Represents a versioned signature with deployment information
      class SignatureVersion
        extend T::Sig

        sig { returns(String) }
        attr_reader :signature_name

        sig { returns(String) }
        attr_reader :version

        sig { returns(String) }
        attr_reader :version_hash

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :configuration

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :metadata

        sig { returns(Time) }
        attr_reader :created_at

        sig { returns(T.nilable(String)) }
        attr_reader :program_id

        sig { returns(T::Boolean) }
        attr_reader :is_deployed

        sig { returns(T.nilable(Float)) }
        attr_reader :performance_score

        sig do
          params(
            signature_name: String,
            version: String,
            configuration: T::Hash[Symbol, T.untyped],
            metadata: T::Hash[Symbol, T.untyped],
            program_id: T.nilable(String),
            is_deployed: T::Boolean,
            performance_score: T.nilable(Float)
          ).void
        end
        def initialize(signature_name:, version:, configuration:, metadata: {}, program_id: nil, is_deployed: false, performance_score: nil)
          @signature_name = signature_name
          @version = version
          @configuration = configuration.freeze
          @metadata = metadata.merge({
            created_at: Time.now.iso8601,
            registry_version: "1.0"
          }).freeze
          @created_at = Time.now
          @program_id = program_id
          @is_deployed = is_deployed
          @performance_score = performance_score
          @version_hash = generate_version_hash
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            signature_name: @signature_name,
            version: @version,
            version_hash: @version_hash,
            configuration: @configuration,
            metadata: @metadata,
            created_at: @created_at.iso8601,
            program_id: @program_id,
            is_deployed: @is_deployed,
            performance_score: @performance_score
          }
        end

        sig { params(data: T::Hash[Symbol, T.untyped]).returns(SignatureVersion) }
        def self.from_h(data)
          version = new(
            signature_name: data[:signature_name],
            version: data[:version],
            configuration: data[:configuration] || {},
            metadata: data[:metadata] || {},
            program_id: data[:program_id],
            is_deployed: data[:is_deployed] || false,
            performance_score: data[:performance_score]
          )
          version.instance_variable_set(:@created_at, Time.parse(data[:created_at])) if data[:created_at]
          version.instance_variable_set(:@version_hash, data[:version_hash]) if data[:version_hash]
          version
        end

        sig { params(score: Float).returns(SignatureVersion) }
        def with_performance_score(score)
          self.class.new(
            signature_name: @signature_name,
            version: @version,
            configuration: @configuration,
            metadata: @metadata,
            program_id: @program_id,
            is_deployed: @is_deployed,
            performance_score: score
          )
        end

        sig { returns(SignatureVersion) }
        def deploy
          self.class.new(
            signature_name: @signature_name,
            version: @version,
            configuration: @configuration,
            metadata: @metadata,
            program_id: @program_id,
            is_deployed: true,
            performance_score: @performance_score
          )
        end

        sig { returns(SignatureVersion) }
        def undeploy
          self.class.new(
            signature_name: @signature_name,
            version: @version,
            configuration: @configuration,
            metadata: @metadata,
            program_id: @program_id,
            is_deployed: false,
            performance_score: @performance_score
          )
        end

        private

        sig { returns(String) }
        def generate_version_hash
          content = "#{@signature_name}_#{@version}_#{@configuration.hash}_#{@created_at.to_f}"
          Digest::SHA256.hexdigest(content)[0, 12]
        end
      end

      # Configuration for the registry
      class RegistryConfig
        extend T::Sig

        sig { returns(String) }
        attr_accessor :registry_path

        sig { returns(String) }
        attr_accessor :config_file

        sig { returns(T::Boolean) }
        attr_accessor :auto_version

        sig { returns(Integer) }
        attr_accessor :max_versions_per_signature

        sig { returns(T::Boolean) }
        attr_accessor :backup_on_deploy

        sig { returns(String) }
        attr_accessor :version_format

        sig { void }
        def initialize
          @registry_path = "./dspy_registry"
          @config_file = "registry.yml"
          @auto_version = true
          @max_versions_per_signature = 10
          @backup_on_deploy = true
          @version_format = "v%Y%m%d_%H%M%S" # timestamp-based versions
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            registry_path: @registry_path,
            config_file: @config_file,
            auto_version: @auto_version,
            max_versions_per_signature: @max_versions_per_signature,
            backup_on_deploy: @backup_on_deploy,
            version_format: @version_format
          }
        end

        sig { params(data: T::Hash[Symbol, T.untyped]).void }
        def from_h(data)
          @registry_path = data[:registry_path] if data[:registry_path]
          @config_file = data[:config_file] if data[:config_file]
          @auto_version = data[:auto_version] if data.key?(:auto_version)
          @max_versions_per_signature = data[:max_versions_per_signature] if data[:max_versions_per_signature]
          @backup_on_deploy = data[:backup_on_deploy] if data.key?(:backup_on_deploy)
          @version_format = data[:version_format] if data[:version_format]
        end
      end

      sig { returns(RegistryConfig) }
      attr_reader :config

      sig { params(config: T.nilable(RegistryConfig)).void }
      def initialize(config: nil)
        @config = config || RegistryConfig.new
        setup_registry_directory
        load_or_create_config
      end

      # Register a new signature version
      sig do
        params(
          signature_name: String,
          configuration: T::Hash[Symbol, T.untyped],
          metadata: T::Hash[Symbol, T.untyped],
          program_id: T.nilable(String),
          version: T.nilable(String)
        ).returns(SignatureVersion)
      end
      def register_version(signature_name, configuration, metadata: {}, program_id: nil, version: nil)
        emit_register_start_event(signature_name, version)

        begin
          version ||= generate_version_name if @config.auto_version

          signature_version = SignatureVersion.new(
            signature_name: signature_name,
            version: version,
            configuration: configuration,
            metadata: metadata,
            program_id: program_id
          )

          # Load existing versions
          versions = load_signature_versions(signature_name)
          
          # Check if version already exists
          if versions.any? { |v| v.version == version }
            raise ArgumentError, "Version #{version} already exists for signature #{signature_name}"
          end

          # Add new version
          versions << signature_version

          # Cleanup old versions if needed
          if @config.max_versions_per_signature > 0 && versions.size > @config.max_versions_per_signature
            versions = versions.sort_by(&:created_at).last(@config.max_versions_per_signature)
          end

          # Save versions
          save_signature_versions(signature_name, versions)

          emit_register_complete_event(signature_version)
          signature_version

        rescue => error
          emit_register_error_event(signature_name, version, error)
          raise
        end
      end

      # Deploy a specific version
      sig { params(signature_name: String, version: String).returns(T.nilable(SignatureVersion)) }
      def deploy_version(signature_name, version)
        emit_deploy_start_event(signature_name, version)

        begin
          versions = load_signature_versions(signature_name)
          target_version = versions.find { |v| v.version == version }

          return nil unless target_version

          # Backup current deployment if configured
          if @config.backup_on_deploy
            current_deployed = get_deployed_version(signature_name)
            if current_deployed
              create_deployment_backup(current_deployed)
            end
          end

          # Mark currently deployed version as previously deployed and undeploy all
          versions = versions.map do |v|
            if v.is_deployed
              # Add deployment history metadata
              updated_metadata = v.metadata.merge(was_deployed: true, last_deployed_at: Time.now.iso8601)
              SignatureVersion.new(
                signature_name: v.signature_name,
                version: v.version,
                configuration: v.configuration,
                metadata: updated_metadata,
                program_id: v.program_id,
                is_deployed: false,
                performance_score: v.performance_score
              )
            else
              v.undeploy
            end
          end

          # Deploy target version
          target_index = versions.index { |v| v.version == version }
          versions[target_index] = target_version.deploy

          save_signature_versions(signature_name, versions)

          deployed_version = versions[target_index]
          emit_deploy_complete_event(deployed_version)
          deployed_version

        rescue => error
          emit_deploy_error_event(signature_name, version, error)
          nil
        end
      end

      # Rollback to previous deployed version
      sig { params(signature_name: String).returns(T.nilable(SignatureVersion)) }
      def rollback(signature_name)
        emit_rollback_start_event(signature_name)

        begin
          versions = load_signature_versions(signature_name)
          
          # Find versions that have deployment history (previously deployed)
          # Look for versions with deployment metadata or that were deployed
          deployed_history = versions.select do |v|
            v.metadata[:was_deployed] || v.is_deployed
          end.sort_by(&:created_at)

          # If we don't have deployment history, check if any versions exist
          if deployed_history.empty?
            # Look for the second newest version as fallback
            all_versions = versions.sort_by(&:created_at)
            if all_versions.size >= 2
              previous_version = all_versions[-2]
              result = deploy_version(signature_name, previous_version.version)
              if result
                emit_rollback_complete_event(result)
              end
              return result
            end
          elsif deployed_history.size >= 2
            # Get the previous deployed version (excluding currently deployed)
            current_deployed = versions.find(&:is_deployed)
            previous_versions = deployed_history.reject { |v| v.version == current_deployed&.version }
            
            if previous_versions.any?
              previous_version = previous_versions.last
              result = deploy_version(signature_name, previous_version.version)
              if result
                emit_rollback_complete_event(result)
              end
              return result
            end
          end

          emit_rollback_error_event(signature_name, "No previous version to rollback to")
          nil

        rescue => error
          emit_rollback_error_event(signature_name, error.message)
          nil
        end
      end

      # Get currently deployed version
      sig { params(signature_name: String).returns(T.nilable(SignatureVersion)) }
      def get_deployed_version(signature_name)
        versions = load_signature_versions(signature_name)
        versions.find(&:is_deployed)
      end

      # List all versions for a signature
      sig { params(signature_name: String).returns(T::Array[SignatureVersion]) }
      def list_versions(signature_name)
        load_signature_versions(signature_name)
      end

      # List all signatures in registry
      sig { returns(T::Array[String]) }
      def list_signatures
        Dir.glob(File.join(@config.registry_path, "signatures", "*.yml")).map do |file|
          File.basename(file, ".yml")
        end
      end

      # Update performance score for a version
      sig { params(signature_name: String, version: String, score: Float).returns(T.nilable(SignatureVersion)) }
      def update_performance_score(signature_name, version, score)
        versions = load_signature_versions(signature_name)
        target_index = versions.index { |v| v.version == version }

        return nil unless target_index

        versions[target_index] = versions[target_index].with_performance_score(score)
        save_signature_versions(signature_name, versions)

        emit_performance_update_event(versions[target_index])
        versions[target_index]
      end

      # Get performance history for a signature
      sig { params(signature_name: String).returns(T::Hash[Symbol, T.untyped]) }
      def get_performance_history(signature_name)
        versions = load_signature_versions(signature_name)
        versions_with_scores = versions.select { |v| v.performance_score }

        return { versions: [], trends: {} } if versions_with_scores.empty?

        sorted_versions = versions_with_scores.sort_by(&:created_at)

        {
          versions: sorted_versions.map do |v|
            {
              version: v.version,
              score: v.performance_score,
              created_at: v.created_at.iso8601,
              is_deployed: v.is_deployed
            }
          end,
          trends: {
            latest_score: sorted_versions.last.performance_score,
            best_score: versions_with_scores.map(&:performance_score).compact.max,
            worst_score: versions_with_scores.map(&:performance_score).compact.min,
            improvement_trend: calculate_improvement_trend(sorted_versions)
          }
        }
      end

      # Compare two versions
      sig do
        params(
          signature_name: String,
          version1: String,
          version2: String
        ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def compare_versions(signature_name, version1, version2)
        versions = load_signature_versions(signature_name)
        v1 = versions.find { |v| v.version == version1 }
        v2 = versions.find { |v| v.version == version2 }

        return nil unless v1 && v2

        {
          version_1: {
            version: v1.version,
            created_at: v1.created_at.iso8601,
            performance_score: v1.performance_score,
            is_deployed: v1.is_deployed,
            configuration: v1.configuration
          },
          version_2: {
            version: v2.version,
            created_at: v2.created_at.iso8601,
            performance_score: v2.performance_score,
            is_deployed: v2.is_deployed,
            configuration: v2.configuration
          },
          comparison: {
            age_difference_hours: ((v1.created_at - v2.created_at) / 3600).round(2),
            performance_difference: (v1.performance_score || 0) - (v2.performance_score || 0),
            configuration_changes: compare_configurations(v1.configuration, v2.configuration)
          }
        }
      end

      # Export registry state
      sig { params(export_path: String).void }
      def export_registry(export_path)
        registry_data = {
          exported_at: Time.now.iso8601,
          config: @config.to_h,
          signatures: {}
        }

        list_signatures.each do |signature_name|
          registry_data[:signatures][signature_name] = load_signature_versions(signature_name).map(&:to_h)
        end

        File.write(export_path, YAML.dump(registry_data))
        emit_export_event(export_path, list_signatures.size)
      end

      # Import registry state
      sig { params(import_path: String).void }
      def import_registry(import_path)
        data = YAML.load_file(import_path, symbolize_names: true)
        imported_count = 0

        data[:signatures].each do |signature_name, versions_data|
          versions = versions_data.map { |v| SignatureVersion.from_h(v) }
          save_signature_versions(signature_name.to_s, versions)
          imported_count += 1
        end

        emit_import_event(import_path, imported_count)
      end

      private

      sig { void }
      def setup_registry_directory
        FileUtils.mkdir_p(@config.registry_path) unless Dir.exist?(@config.registry_path)
        
        signatures_dir = File.join(@config.registry_path, "signatures")
        FileUtils.mkdir_p(signatures_dir) unless Dir.exist?(signatures_dir)

        backups_dir = File.join(@config.registry_path, "backups")
        FileUtils.mkdir_p(backups_dir) unless Dir.exist?(backups_dir)
      end

      sig { void }
      def load_or_create_config
        config_path = File.join(@config.registry_path, @config.config_file)
        
        if File.exist?(config_path)
          config_data = YAML.load_file(config_path, symbolize_names: true)
          @config.from_h(config_data)
        else
          save_config
        end
      end

      sig { void }
      def save_config
        config_path = File.join(@config.registry_path, @config.config_file)
        File.write(config_path, YAML.dump(@config.to_h))
      end

      sig { returns(String) }
      def generate_version_name
        Time.now.strftime(@config.version_format)
      end

      sig { params(signature_name: String).returns(T::Array[SignatureVersion]) }
      def load_signature_versions(signature_name)
        file_path = signature_file_path(signature_name)
        
        return [] unless File.exist?(file_path)

        versions_data = YAML.load_file(file_path, symbolize_names: true)
        versions_data.map { |data| SignatureVersion.from_h(data) }
      end

      sig { params(signature_name: String, versions: T::Array[SignatureVersion]).void }
      def save_signature_versions(signature_name, versions)
        file_path = signature_file_path(signature_name)
        versions_data = versions.map(&:to_h)
        File.write(file_path, YAML.dump(versions_data))
      end

      sig { params(signature_name: String).returns(String) }
      def signature_file_path(signature_name)
        File.join(@config.registry_path, "signatures", "#{signature_name}.yml")
      end

      sig { params(version: SignatureVersion).void }
      def create_deployment_backup(version)
        backup_dir = File.join(@config.registry_path, "backups", version.signature_name)
        FileUtils.mkdir_p(backup_dir) unless Dir.exist?(backup_dir)
        
        backup_file = File.join(backup_dir, "#{version.version}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.yml")
        File.write(backup_file, YAML.dump(version.to_h))
      end

      sig { params(versions: T::Array[SignatureVersion]).returns(Float) }
      def calculate_improvement_trend(versions)
        return 0.0 if versions.size < 2

        scores = versions.map(&:performance_score).compact
        return 0.0 if scores.size < 2

        # Simple linear trend calculation
        recent_scores = scores.last([scores.size / 2, 2].max)
        older_scores = scores.first([scores.size / 2, 2].max)

        recent_avg = recent_scores.sum.to_f / recent_scores.size
        older_avg = older_scores.sum.to_f / older_scores.size

        return 0.0 if older_avg == 0.0

        ((recent_avg - older_avg) / older_avg * 100).round(2)
      end

      sig { params(config1: T::Hash[Symbol, T.untyped], config2: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
      def compare_configurations(config1, config2)
        changes = []
        
        all_keys = (config1.keys + config2.keys).uniq
        
        all_keys.each do |key|
          if !config1.key?(key)
            changes << "Added #{key}: #{config2[key]}"
          elsif !config2.key?(key)
            changes << "Removed #{key}: #{config1[key]}"
          elsif config1[key] != config2[key]
            changes << "Changed #{key}: #{config1[key]} → #{config2[key]}"
          end
        end
        
        changes
      end

      # Event emission methods
      sig { params(signature_name: String, version: T.nilable(String)).void }
      def emit_register_start_event(signature_name, version)
        DSPy.log('registry.register_start',
          'registry.signature_name' => signature_name,
          'registry.version' => version
        )
      end

      sig { params(version: SignatureVersion).void }
      def emit_register_complete_event(version)
        DSPy.log('registry.register_complete',
          'registry.signature_name' => version.signature_name,
          'registry.version' => version.version,
          'registry.version_hash' => version.version_hash
        )
      end

      sig { params(signature_name: String, version: T.nilable(String), error: Exception).void }
      def emit_register_error_event(signature_name, version, error)
        DSPy.log('registry.register_error',
          'registry.signature_name' => signature_name,
          'registry.version' => version,
          'registry.error' => error.message
        )
      end

      sig { params(signature_name: String, version: String).void }
      def emit_deploy_start_event(signature_name, version)
        DSPy.log('registry.deploy_start',
          'registry.signature_name' => signature_name,
          'registry.version' => version
        )
      end

      sig { params(version: SignatureVersion).void }
      def emit_deploy_complete_event(version)
        DSPy.log('registry.deploy_complete',
          'registry.signature_name' => version.signature_name,
          'registry.version' => version.version,
          'registry.performance_score' => version.performance_score
        )
      end

      sig { params(signature_name: String, version: String, error: Exception).void }
      def emit_deploy_error_event(signature_name, version, error)
        DSPy.log('registry.deploy_error',
          'registry.signature_name' => signature_name,
          'registry.version' => version,
          'registry.error' => error.message
        )
      end

      sig { params(signature_name: String).void }
      def emit_rollback_start_event(signature_name)
        DSPy.log('registry.rollback_start',
          'registry.signature_name' => signature_name
        )
      end

      sig { params(version: SignatureVersion).void }
      def emit_rollback_complete_event(version)
        DSPy.log('registry.rollback_complete',
          'registry.signature_name' => version.signature_name,
          'registry.version' => version.version
        )
      end

      sig { params(signature_name: String, error_message: String).void }
      def emit_rollback_error_event(signature_name, error_message)
        DSPy.log('registry.rollback_error',
          'registry.signature_name' => signature_name,
          'registry.error' => error_message
        )
      end

      sig { params(version: SignatureVersion).void }
      def emit_performance_update_event(version)
        DSPy.log('registry.performance_update',
          'registry.signature_name' => version.signature_name,
          'registry.version' => version.version,
          'registry.performance_score' => version.performance_score
        )
      end

      sig { params(export_path: String, signature_count: Integer).void }
      def emit_export_event(export_path, signature_count)
        DSPy.log('registry.export',
          'registry.export_path' => export_path,
          'registry.signature_count' => signature_count
        )
      end

      sig { params(import_path: String, signature_count: Integer).void }
      def emit_import_event(import_path, signature_count)
        DSPy.log('registry.import',
          'registry.import_path' => import_path,
          'registry.signature_count' => signature_count
        )
      end
    end
  end
end