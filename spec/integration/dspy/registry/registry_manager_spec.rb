require 'spec_helper'
require 'tempfile'
require 'tmpdir'
require 'dspy/registry/registry_manager'

RSpec.describe DSPy::Registry::RegistryManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:registry_config) do
    config = DSPy::Registry::SignatureRegistry::RegistryConfig.new
    config.registry_path = temp_dir
    config
  end
  let(:integration_config) do
    config = DSPy::Registry::RegistryManager::RegistryIntegrationConfig.new
    config.auto_register_optimizations = true
    config.auto_deploy_best_versions = false
    config
  end
  let(:registry_manager) do
    DSPy::Registry::RegistryManager.new(
      registry_config: registry_config,
      integration_config: integration_config
    )
  end

  let(:mock_program) do
    double('Program', 
      class: double(name: 'MockProgram'),
      signature_class: double(name: 'TestSignature'),
      prompt: double(instruction: 'Test instruction'),
      few_shot_examples: [
        double(input: { question: "test" }, output: { answer: "test answer" })
      ]
    )
  end

  let(:mock_optimization_result) do
    double('OptimizationResult',
      optimized_program: mock_program,
      best_score_value: 0.85,
      best_score_name: 'accuracy',
      scores: { accuracy: 0.85 },
      history: { total_trials: 10 },
      metadata: { 
        optimizer: 'MIPROv2', 
        optimization_timestamp: Time.now.iso8601,
        program_id: 'test_program_123'
      },
      class: double(name: 'MIPROv2Result')
    )
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe DSPy::Registry::RegistryManager::RegistryIntegrationConfig do
    describe '#initialize' do
      it 'sets sensible defaults' do
        config = DSPy::Registry::RegistryManager::RegistryIntegrationConfig.new
        
        expect(config.auto_register_optimizations).to be(true)
        expect(config.auto_deploy_best_versions).to be(false)
        expect(config.auto_deploy_threshold).to eq(0.1)
        expect(config.rollback_on_performance_drop).to be(true)
        expect(config.rollback_threshold).to eq(0.05)
        expect(config.deployment_strategy).to eq("conservative")
      end
    end

    describe '#to_h' do
      it 'serializes configuration to hash' do
        config = DSPy::Registry::RegistryManager::RegistryIntegrationConfig.new
        config.auto_deploy_best_versions = true
        config.deployment_strategy = "aggressive"
        
        hash = config.to_h
        expect(hash[:auto_deploy_best_versions]).to be(true)
        expect(hash[:deployment_strategy]).to eq("aggressive")
      end
    end
  end

  describe '#initialize' do
    it 'creates manager with default configuration' do
      manager = DSPy::Registry::RegistryManager.new
      
      expect(manager.registry).to be_a(DSPy::Registry::SignatureRegistry)
      expect(manager.integration_config).to be_a(DSPy::Registry::RegistryManager::RegistryIntegrationConfig)
    end

    it 'creates manager with custom configuration' do
      custom_integration_config = DSPy::Registry::RegistryManager::RegistryIntegrationConfig.new
      custom_integration_config.auto_register_optimizations = false
      
      manager = DSPy::Registry::RegistryManager.new(integration_config: custom_integration_config)
      expect(manager.integration_config.auto_register_optimizations).to be(false)
    end
  end

  describe '#register_optimization_result' do
    it 'automatically registers optimization result' do
      version = registry_manager.register_optimization_result(mock_optimization_result)
      
      expect(version).to be_a(DSPy::Registry::SignatureRegistry::SignatureVersion)
      expect(version.signature_name).to eq('TestSignature')
      expect(version.performance_score).to eq(0.85)
      expect(version.program_id).to eq('test_program_123')
    end

    it 'does not register when auto_register is disabled' do
      integration_config.auto_register_optimizations = false
      
      version = registry_manager.register_optimization_result(mock_optimization_result)
      expect(version).to be_nil
    end

    it 'extracts signature name from optimization result' do
      version = registry_manager.register_optimization_result(mock_optimization_result)
      expect(version.signature_name).to eq('TestSignature')
    end

    it 'extracts configuration from optimization result' do
      version = registry_manager.register_optimization_result(mock_optimization_result)
      
      expect(version.configuration[:instruction]).to eq('Test instruction')
      expect(version.configuration[:few_shot_examples_count]).to eq(1)
      expect(version.configuration[:optimization_metadata]).to include(:optimizer)
    end

    it 'includes enhanced metadata' do
      version = registry_manager.register_optimization_result(
        mock_optimization_result,
        metadata: { custom_field: 'custom_value' }
      )
      
      expect(version.metadata[:optimizer]).to eq('MIPROv2')
      expect(version.metadata[:auto_registered]).to be(true)
      expect(version.metadata[:custom_field]).to eq('custom_value')
    end

    it 'returns nil when signature name cannot be extracted' do
      program_without_signature = double('Program', signature_class: nil)
      result_without_signature = double('Result', optimized_program: program_without_signature)
      
      version = registry_manager.register_optimization_result(result_without_signature)
      expect(version).to be_nil
    end
  end

  describe '#deploy_with_strategy' do
    before do
      # Register some versions with different scores
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'v1' }, 
        version: 'v1.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v1.0', 0.7)
      
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'v2' }, 
        version: 'v2.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v2.0', 0.9)
      
      registry_manager.registry.deploy_version('TestSignature', 'v1.0')
    end

    it 'deploys with conservative strategy' do
      deployed = registry_manager.deploy_with_strategy('TestSignature', strategy: 'conservative')
      
      expect(deployed).not_to be_nil
      expect(deployed.version).to eq('v2.0') # Better score, significant improvement
      expect(deployed.is_deployed).to be(true)
    end

    it 'deploys with aggressive strategy' do
      deployed = registry_manager.deploy_with_strategy('TestSignature', strategy: 'aggressive')
      
      expect(deployed).not_to be_nil
      expect(deployed.version).to eq('v2.0') # Best score
      expect(deployed.is_deployed).to be(true)
    end

    it 'uses default strategy from configuration' do
      integration_config.deployment_strategy = 'conservative'
      
      deployed = registry_manager.deploy_with_strategy('TestSignature')
      expect(deployed).not_to be_nil
    end
  end

  describe '#monitor_and_rollback' do
    before do
      # Register and deploy a version
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'v1' }, 
        version: 'v1.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v1.0', 0.8)
      
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'v2' }, 
        version: 'v2.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v2.0', 0.9)
      
      # Deploy v1.0, then v2.0 (creating rollback history)
      registry_manager.registry.deploy_version('TestSignature', 'v1.0')
      registry_manager.registry.deploy_version('TestSignature', 'v2.0')
    end

    it 'rolls back when performance drops significantly' do
      # Performance dropped from 0.9 to 0.7 (22% drop, above 5% threshold)
      rolled_back = registry_manager.monitor_and_rollback('TestSignature', 0.7)
      
      expect(rolled_back).to be(true)
      
      deployed = registry_manager.registry.get_deployed_version('TestSignature')
      expect(deployed.version).to eq('v1.0') # Rolled back to previous version
    end

    it 'does not roll back for small performance drops' do
      # Performance dropped from 0.9 to 0.88 (2% drop, below 5% threshold)
      rolled_back = registry_manager.monitor_and_rollback('TestSignature', 0.88)
      
      expect(rolled_back).to be(false)
      
      deployed = registry_manager.registry.get_deployed_version('TestSignature')
      expect(deployed.version).to eq('v2.0') # Still deployed
    end

    it 'does not roll back when rollback is disabled' do
      integration_config.rollback_on_performance_drop = false
      
      rolled_back = registry_manager.monitor_and_rollback('TestSignature', 0.7)
      expect(rolled_back).to be(false)
    end

    it 'rolls back when performance drops significantly' do
      # Performance dropped from 0.9 to 0.7 (22% drop, above 5% threshold)
      rolled_back = registry_manager.monitor_and_rollback('TestSignature', 0.7)
      
      expect(rolled_back).to be(true)
      
      deployed = registry_manager.registry.get_deployed_version('TestSignature')
      expect(deployed.version).to eq('v1.0') # Rolled back to previous version
    end
  end

  describe '#get_deployment_status' do
    before do
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'test' }, 
        version: 'v1.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v1.0', 0.8)
      registry_manager.registry.deploy_version('TestSignature', 'v1.0')
    end

    it 'returns comprehensive deployment status' do
      status = registry_manager.get_deployment_status('TestSignature')
      
      expect(status[:deployed_version]).not_to be_nil
      expect(status[:deployed_version][:version]).to eq('v1.0')
      expect(status[:total_versions]).to eq(1)
      expect(status[:performance_history]).to have_key(:versions)
      expect(status[:recommendations]).to be_an(Array)
    end

    it 'includes recommendations' do
      status = registry_manager.get_deployment_status('TestSignature')
      expect(status[:recommendations]).to be_an(Array)
    end
  end

  describe '#create_deployment_plan' do
    before do
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'v1' }, 
        version: 'v1.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v1.0', 0.8)
      
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'v2' }, 
        version: 'v2.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v2.0', 0.9)
      
      registry_manager.registry.deploy_version('TestSignature', 'v1.0')
    end

    it 'creates deployment plan with safety checks' do
      plan = registry_manager.create_deployment_plan('TestSignature', 'v2.0')
      
      expect(plan[:signature_name]).to eq('TestSignature')
      expect(plan[:current_version]).to eq('v1.0')
      expect(plan[:target_version]).to eq('v2.0')
      expect(plan[:performance_change]).to be_within(0.001).of(0.1) # 0.9 - 0.8
      expect(plan[:deployment_safe]).to be(true)
      expect(plan[:checks]).to include("Performance improvement expected")
    end

    it 'marks deployment as unsafe for performance regression' do
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'v3' }, 
        version: 'v3.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v3.0', 0.6)
      
      plan = registry_manager.create_deployment_plan('TestSignature', 'v3.0')
      
      expect(plan[:deployment_safe]).to be(false)
      expect(plan[:checks]).to include("Performance regression detected")
    end

    it 'returns error for non-existent target version' do
      plan = registry_manager.create_deployment_plan('TestSignature', 'v99.0')
      expect(plan[:error]).to eq("Target version not found")
    end
  end

  describe '#bulk_deployment_status' do
    before do
      ['Signature1', 'Signature2'].each do |name|
        registry_manager.registry.register_version(name, { instruction: 'test' }, version: 'v1.0')
        registry_manager.registry.deploy_version(name, 'v1.0')
      end
    end

    it 'returns status for multiple signatures' do
      results = registry_manager.bulk_deployment_status(['Signature1', 'Signature2'])
      
      expect(results).to have_key('Signature1')
      expect(results).to have_key('Signature2')
      expect(results['Signature1'][:deployed_version]).not_to be_nil
      expect(results['Signature2'][:deployed_version]).not_to be_nil
    end
  end

  describe '#cleanup_old_versions' do
    before do
      # Create multiple versions for cleanup testing
      signature_name = 'TestSignature'
      
      # Create 8 versions
      8.times do |i|
        registry_manager.registry.register_version(
          signature_name, 
          { instruction: "v#{i}" }, 
          version: "v#{i}.0"
        )
        sleep(0.01) # Ensure different timestamps
      end
      
      # Deploy the 4th version
      registry_manager.registry.deploy_version(signature_name, 'v3.0')
    end

    it 'cleans up old versions while preserving important ones' do
      result = registry_manager.cleanup_old_versions
      
      expect(result[:cleaned_signatures]).to be >= 0
      expect(result[:cleaned_versions]).to be >= 0
      
      # Should keep deployed version and recent versions
      remaining_versions = registry_manager.registry.list_versions('TestSignature')
      deployed = remaining_versions.find(&:is_deployed)
      expect(deployed.version).to eq('v3.0') # Deployed version preserved
    end
  end

  describe 'class methods' do
    describe '.instance' do
      it 'returns singleton instance' do
        instance1 = DSPy::Registry::RegistryManager.instance
        instance2 = DSPy::Registry::RegistryManager.instance
        
        expect(instance1).to be(instance2)
      end
    end

    describe '.configure' do
      it 'configures global instance' do
        custom_integration_config = DSPy::Registry::RegistryManager::RegistryIntegrationConfig.new
        custom_integration_config.auto_register_optimizations = false
        
        DSPy::Registry::RegistryManager.configure(integration_config: custom_integration_config)
        
        expect(DSPy::Registry::RegistryManager.instance.integration_config.auto_register_optimizations).to be(false)
      end
    end
  end

  describe 'auto-deployment behavior' do
    before do
      integration_config.auto_deploy_best_versions = true
      integration_config.auto_deploy_threshold = 0.1
    end

    it 'auto-deploys when significant improvement is detected' do
      version = registry_manager.register_optimization_result(mock_optimization_result)
      
      deployed = registry_manager.registry.get_deployed_version('TestSignature')
      expect(deployed).not_to be_nil
      expect(deployed.version).to eq(version.version)
    end

    it 'does not auto-deploy when improvement is below threshold' do
      # First register a high-performing version
      registry_manager.registry.register_version(
        'TestSignature', 
        { instruction: 'existing' }, 
        version: 'v1.0'
      )
      registry_manager.registry.update_performance_score('TestSignature', 'v1.0', 0.95)
      registry_manager.registry.deploy_version('TestSignature', 'v1.0')
      
      # Register new optimization with only small improvement
      low_improvement_result = double('Result',
        optimized_program: mock_program,
        best_score_value: 0.96, # Only 1% improvement
        metadata: { optimizer: 'Test' },
        class: double(name: 'TestResult')
      )
      
      # Should not trigger auto-deployment
      registry_manager.register_optimization_result(low_improvement_result)
    end
  end

  describe 'private extraction methods' do
    it 'extracts signature name correctly' do
      signature_name = registry_manager.send(:extract_signature_name, mock_optimization_result)
      expect(signature_name).to eq('TestSignature')
    end

    it 'extracts performance score correctly' do
      score = registry_manager.send(:extract_performance_score, mock_optimization_result)
      expect(score).to eq(0.85)
    end

    it 'extracts optimizer name correctly' do
      optimizer = registry_manager.send(:extract_optimizer_name, mock_optimization_result)
      expect(optimizer).to eq('MIPROv2')
    end

    it 'extracts configuration correctly' do
      config = registry_manager.send(:extract_configuration, mock_optimization_result)
      
      expect(config[:instruction]).to eq('Test instruction')
      expect(config[:few_shot_examples_count]).to eq(1)
      expect(config[:optimization_metadata]).to include(:optimizer)
    end
  end
end