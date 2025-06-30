# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'signature_registry'

module DSPy
  module Registry
    # High-level registry manager that integrates with the DSPy ecosystem
    # Provides automatic version management and integration with optimization results
    class RegistryManager
      extend T::Sig

      # Configuration for automatic registry integration
      class RegistryIntegrationConfig
        extend T::Sig

        sig { returns(T::Boolean) }
        attr_accessor :auto_register_optimizations

        sig { returns(T::Boolean) }
        attr_accessor :auto_deploy_best_versions

        sig { returns(Float) }
        attr_accessor :auto_deploy_threshold

        sig { returns(T::Boolean) }
        attr_accessor :rollback_on_performance_drop

        sig { returns(Float) }
        attr_accessor :rollback_threshold

        sig { returns(String) }
        attr_accessor :deployment_strategy

        sig { void }
        def initialize
          @auto_register_optimizations = true
          @auto_deploy_best_versions = false
          @auto_deploy_threshold = 0.1  # 10% improvement
          @rollback_on_performance_drop = true
          @rollback_threshold = 0.05    # 5% drop
          @deployment_strategy = "conservative" # conservative, aggressive, manual
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            auto_register_optimizations: @auto_register_optimizations,
            auto_deploy_best_versions: @auto_deploy_best_versions,
            auto_deploy_threshold: @auto_deploy_threshold,
            rollback_on_performance_drop: @rollback_on_performance_drop,
            rollback_threshold: @rollback_threshold,
            deployment_strategy: @deployment_strategy
          }
        end
      end

      sig { returns(SignatureRegistry) }
      attr_reader :registry

      sig { returns(RegistryIntegrationConfig) }
      attr_reader :integration_config

      sig do
        params(
          registry_config: T.nilable(SignatureRegistry::RegistryConfig),
          integration_config: T.nilable(RegistryIntegrationConfig)
        ).void
      end
      def initialize(registry_config: nil, integration_config: nil)
        @registry = SignatureRegistry.new(config: registry_config)
        @integration_config = integration_config || RegistryIntegrationConfig.new
      end

      # Register an optimization result automatically
      sig do
        params(
          optimization_result: T.untyped,
          signature_name: T.nilable(String),
          metadata: T::Hash[Symbol, T.untyped]
        ).returns(T.nilable(SignatureRegistry::SignatureVersion))
      end
      def register_optimization_result(optimization_result, signature_name: nil, metadata: {})
        return nil unless @integration_config.auto_register_optimizations

        # Extract signature name if not provided
        signature_name ||= extract_signature_name(optimization_result)
        return nil unless signature_name

        # Extract configuration from optimization result
        configuration = extract_configuration(optimization_result)
        
        # Get performance score
        performance_score = extract_performance_score(optimization_result)

        # Enhanced metadata
        enhanced_metadata = metadata.merge({
          optimizer: extract_optimizer_name(optimization_result),
          optimization_timestamp: extract_optimization_timestamp(optimization_result),
          trials_count: extract_trials_count(optimization_result),
          auto_registered: true
        })

        # Register the version
        version = @registry.register_version(
          signature_name,
          configuration,
          metadata: enhanced_metadata,
          program_id: extract_program_id(optimization_result)
        )

        # Update performance score
        if performance_score
          @registry.update_performance_score(signature_name, version.version, performance_score)
          version = version.with_performance_score(performance_score)
        end

        # Check for auto-deployment
        check_auto_deployment(signature_name, version)

        version
      end

      # Create a deployment strategy
      sig { params(signature_name: String, strategy: String).returns(T.nilable(SignatureRegistry::SignatureVersion)) }
      def deploy_with_strategy(signature_name, strategy: nil)
        strategy ||= @integration_config.deployment_strategy

        case strategy
        when "conservative"
          deploy_conservative(signature_name)
        when "aggressive"
          deploy_aggressive(signature_name)
        when "best_score"
          deploy_best_score(signature_name)
        else
          nil
        end
      end

      # Monitor and rollback if needed
      sig { params(signature_name: String, current_score: Float).returns(T::Boolean) }
      def monitor_and_rollback(signature_name, current_score)
        return false unless @integration_config.rollback_on_performance_drop

        deployed_version = @registry.get_deployed_version(signature_name)
        return false unless deployed_version&.performance_score

        # Check if performance dropped significantly
        performance_drop = deployed_version.performance_score - current_score
        threshold_drop = deployed_version.performance_score * @integration_config.rollback_threshold

        if performance_drop > threshold_drop
          rollback_result = @registry.rollback(signature_name)
          emit_automatic_rollback_event(signature_name, current_score, deployed_version.performance_score)
          !rollback_result.nil?
        else
          false
        end
      end

      # Get deployment status and recommendations
      sig { params(signature_name: String).returns(T::Hash[Symbol, T.untyped]) }
      def get_deployment_status(signature_name)
        deployed_version = @registry.get_deployed_version(signature_name)
        all_versions = @registry.list_versions(signature_name)
        performance_history = @registry.get_performance_history(signature_name)

        recommendations = generate_deployment_recommendations(signature_name, all_versions, deployed_version)

        {
          deployed_version: deployed_version&.to_h,
          total_versions: all_versions.size,
          performance_history: performance_history,
          recommendations: recommendations,
          last_updated: all_versions.max_by(&:created_at)&.created_at&.iso8601
        }
      end

      # Create a safe deployment plan
      sig { params(signature_name: String, target_version: String).returns(T::Hash[Symbol, T.untyped]) }
      def create_deployment_plan(signature_name, target_version)
        current_deployed = @registry.get_deployed_version(signature_name)
        target = @registry.list_versions(signature_name).find { |v| v.version == target_version }

        return { error: "Target version not found" } unless target

        plan = {
          signature_name: signature_name,
          current_version: current_deployed&.version,
          target_version: target_version,
          deployment_safe: true,
          checks: [],
          recommendations: []
        }

        # Performance check
        if current_deployed&.performance_score && target.performance_score
          performance_change = target.performance_score - current_deployed.performance_score
          plan[:performance_change] = performance_change
          
          if performance_change < 0
            plan[:checks] << "Performance regression detected"
            plan[:deployment_safe] = false
          else
            plan[:checks] << "Performance improvement expected"
          end
        else
          plan[:checks] << "No performance data available"
          plan[:recommendations] << "Run evaluation before deployment"
        end

        # Version age check
        if target.created_at < (Time.now - 7 * 24 * 60 * 60) # 7 days old
          plan[:recommendations] << "Target version is more than 7 days old"
        end

        # Configuration complexity check
        config_complexity = estimate_configuration_complexity(target.configuration)
        if config_complexity > 0.8
          plan[:recommendations] << "Complex configuration detected - consider gradual rollout"
        end

        plan
      end

      # Bulk operations for managing multiple signatures
      sig { params(signature_names: T::Array[String]).returns(T::Hash[String, T.untyped]) }
      def bulk_deployment_status(signature_names)
        results = {}
        
        signature_names.each do |name|
          results[name] = get_deployment_status(name)
        end

        results
      end

      # Clean up old versions across all signatures
      sig { returns(T::Hash[Symbol, Integer]) }
      def cleanup_old_versions
        cleaned_signatures = 0
        cleaned_versions = 0

        @registry.list_signatures.each do |signature_name|
          versions = @registry.list_versions(signature_name)
          
          # Keep deployed version and recent versions
          deployed_version = versions.find(&:is_deployed)
          recent_versions = versions.sort_by(&:created_at).last(5)
          
          keep_versions = [deployed_version, *recent_versions].compact.uniq
          
          if keep_versions.size < versions.size
            @registry.send(:save_signature_versions, signature_name, keep_versions)
            cleaned_signatures += 1
            cleaned_versions += (versions.size - keep_versions.size)
          end
        end

        {
          cleaned_signatures: cleaned_signatures,
          cleaned_versions: cleaned_versions
        }
      end

      # Global registry instance
      @@instance = T.let(nil, T.nilable(RegistryManager))

      sig { returns(RegistryManager) }
      def self.instance
        @@instance ||= new
      end

      sig { params(registry_config: SignatureRegistry::RegistryConfig, integration_config: RegistryIntegrationConfig).void }
      def self.configure(registry_config: nil, integration_config: nil)
        @@instance = new(registry_config: registry_config, integration_config: integration_config)
      end

      private

      sig { params(optimization_result: T.untyped).returns(T.nilable(String)) }
      def extract_signature_name(optimization_result)
        if optimization_result.respond_to?(:optimized_program)
          program = optimization_result.optimized_program
          if program.respond_to?(:signature_class)
            program.signature_class&.name
          end
        end
      end

      sig { params(optimization_result: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def extract_configuration(optimization_result)
        config = {}

        if optimization_result.respond_to?(:optimized_program)
          program = optimization_result.optimized_program
          
          # Extract instruction
          if program.respond_to?(:prompt) && program.prompt.respond_to?(:instruction)
            config[:instruction] = program.prompt.instruction
          end

          # Extract few-shot examples
          if program.respond_to?(:few_shot_examples)
            config[:few_shot_examples_count] = program.few_shot_examples.size
            config[:few_shot_examples] = program.few_shot_examples.map do |example|
              {
                input: example.respond_to?(:input) ? example.input : nil,
                output: example.respond_to?(:output) ? example.output : nil
              }
            end
          end
        end

        # Extract optimization metadata
        if optimization_result.respond_to?(:metadata)
          config[:optimization_metadata] = optimization_result.metadata
        end

        config
      end

      sig { params(optimization_result: T.untyped).returns(T.nilable(Float)) }
      def extract_performance_score(optimization_result)
        if optimization_result.respond_to?(:best_score_value)
          optimization_result.best_score_value
        elsif optimization_result.respond_to?(:scores) && optimization_result.scores.is_a?(Hash)
          optimization_result.scores.values.first
        end
      end

      sig { params(optimization_result: T.untyped).returns(T.nilable(String)) }
      def extract_optimizer_name(optimization_result)
        if optimization_result.respond_to?(:metadata) && optimization_result.metadata[:optimizer]
          optimization_result.metadata[:optimizer]
        else
          optimization_result.class.name
        end
      end

      sig { params(optimization_result: T.untyped).returns(T.nilable(String)) }
      def extract_optimization_timestamp(optimization_result)
        if optimization_result.respond_to?(:metadata)
          optimization_result.metadata[:optimization_timestamp]
        end
      end

      sig { params(optimization_result: T.untyped).returns(T.nilable(Integer)) }
      def extract_trials_count(optimization_result)
        if optimization_result.respond_to?(:history) && optimization_result.history[:total_trials]
          optimization_result.history[:total_trials]
        end
      end

      sig { params(optimization_result: T.untyped).returns(T.nilable(String)) }
      def extract_program_id(optimization_result)
        # This would typically come from storage system
        if optimization_result.respond_to?(:metadata) && optimization_result.metadata[:program_id]
          optimization_result.metadata[:program_id]
        end
      end

      sig { params(signature_name: String, version: SignatureRegistry::SignatureVersion).void }
      def check_auto_deployment(signature_name, version)
        return unless @integration_config.auto_deploy_best_versions
        return unless version.performance_score

        deployed_version = @registry.get_deployed_version(signature_name)
        
        should_deploy = if deployed_version&.performance_score
          improvement = version.performance_score - deployed_version.performance_score
          improvement >= @integration_config.auto_deploy_threshold
        else
          true # No current deployment, deploy this one
        end

        if should_deploy
          @registry.deploy_version(signature_name, version.version)
          emit_auto_deployment_event(signature_name, version.version)
        end
      end

      sig { params(signature_name: String).returns(T.nilable(SignatureRegistry::SignatureVersion)) }
      def deploy_conservative(signature_name)
        versions = @registry.list_versions(signature_name)
        deployed = @registry.get_deployed_version(signature_name)

        # Only deploy if significantly better than current
        candidates = versions.select { |v| v.performance_score }
        return nil if candidates.empty?

        best_candidate = candidates.max_by(&:performance_score)
        
        if deployed&.performance_score
          improvement = best_candidate.performance_score - deployed.performance_score
          threshold = deployed.performance_score * 0.1 # 10% improvement required
          
          if improvement >= threshold
            @registry.deploy_version(signature_name, best_candidate.version)
          else
            nil
          end
        else
          @registry.deploy_version(signature_name, best_candidate.version)
        end
      end

      sig { params(signature_name: String).returns(T.nilable(SignatureRegistry::SignatureVersion)) }
      def deploy_aggressive(signature_name)
        versions = @registry.list_versions(signature_name)
        candidates = versions.select { |v| v.performance_score }
        return nil if candidates.empty?

        # Deploy the best version regardless of current deployment
        best_candidate = candidates.max_by(&:performance_score)
        @registry.deploy_version(signature_name, best_candidate.version)
      end

      sig { params(signature_name: String).returns(T.nilable(SignatureRegistry::SignatureVersion)) }
      def deploy_best_score(signature_name)
        deploy_aggressive(signature_name) # Same as aggressive for now
      end

      sig do
        params(
          signature_name: String,
          versions: T::Array[SignatureRegistry::SignatureVersion],
          deployed: T.nilable(SignatureRegistry::SignatureVersion)
        ).returns(T::Array[String])
      end
      def generate_deployment_recommendations(signature_name, versions, deployed)
        recommendations = []

        if deployed.nil?
          if versions.any? { |v| v.performance_score }
            recommendations << "No version deployed - consider deploying best performing version"
          else
            recommendations << "No version deployed - run evaluation on versions before deployment"
          end
        else
          # Check for better versions
          better_versions = versions.select do |v|
            v.performance_score && 
            deployed.performance_score && 
            v.performance_score > deployed.performance_score
          end

          if better_versions.any?
            best = better_versions.max_by(&:performance_score)
            improvement = ((best.performance_score - deployed.performance_score) / deployed.performance_score * 100).round(1)
            recommendations << "Version #{best.version} shows #{improvement}% improvement"
          end

          # Check for old deployment
          if deployed.created_at < (Time.now - 30 * 24 * 60 * 60) # 30 days
            recommendations << "Current deployment is over 30 days old - consider updating"
          end
        end

        recommendations
      end

      sig { params(configuration: T::Hash[Symbol, T.untyped]).returns(Float) }
      def estimate_configuration_complexity(configuration)
        complexity = 0.0
        
        # Instruction complexity
        if configuration[:instruction]
          instruction_length = configuration[:instruction].length
          complexity += [instruction_length / 1000.0, 0.5].min
        end

        # Few-shot examples complexity
        if configuration[:few_shot_examples_count]
          examples_complexity = [configuration[:few_shot_examples_count] / 10.0, 0.5].min
          complexity += examples_complexity
        end

        [complexity, 1.0].min
      end

      sig { params(signature_name: String, version: String).void }
      def emit_auto_deployment_event(signature_name, version)
        DSPy::Instrumentation.emit('dspy.registry.auto_deployment', {
          signature_name: signature_name,
          version: version,
          timestamp: Time.now.iso8601
        })
      end

      sig { params(signature_name: String, current_score: Float, previous_score: Float).void }
      def emit_automatic_rollback_event(signature_name, current_score, previous_score)
        DSPy::Instrumentation.emit('dspy.registry.automatic_rollback', {
          signature_name: signature_name,
          current_score: current_score,
          previous_score: previous_score,
          performance_drop: previous_score - current_score,
          timestamp: Time.now.iso8601
        })
      end
    end
  end
end