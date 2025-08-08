require 'spec_helper'
require 'tempfile'
require 'tmpdir'
require 'dspy/registry/signature_registry'

RSpec.describe DSPy::Registry::SignatureRegistry do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config) do
    config = DSPy::Registry::SignatureRegistry::RegistryConfig.new
    config.registry_path = temp_dir
    config.auto_version = true
    config
  end
  let(:registry) { DSPy::Registry::SignatureRegistry.new(config: config) }
  
  let(:test_configuration) do
    {
      instruction: "Test instruction for signature",
      few_shot_examples_count: 3,
      optimization_metadata: { trials: 10, best_score: 0.85 }
    }
  end

  let(:test_metadata) do
    {
      optimizer: "MIPROv2",
      optimization_timestamp: Time.now.iso8601,
      trials_count: 10
    }
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe DSPy::Registry::SignatureRegistry::RegistryConfig do
    describe '#initialize' do
      it 'sets sensible defaults' do
        config = DSPy::Registry::SignatureRegistry::RegistryConfig.new
        
        expect(config.registry_path).to eq("./dspy_registry")
        expect(config.auto_version).to be(true)
        expect(config.max_versions_per_signature).to eq(10)
        expect(config.backup_on_deploy).to be(true)
        expect(config.version_format).to eq("v%Y%m%d_%H%M%S")
      end
    end

    describe '#to_h and #from_h' do
      it 'serializes and deserializes correctly' do
        config = DSPy::Registry::SignatureRegistry::RegistryConfig.new
        config.max_versions_per_signature = 5
        config.auto_version = false
        
        hash = config.to_h
        new_config = DSPy::Registry::SignatureRegistry::RegistryConfig.new
        new_config.from_h(hash)
        
        expect(new_config.max_versions_per_signature).to eq(5)
        expect(new_config.auto_version).to be(false)
      end
    end
  end

  describe DSPy::Registry::SignatureRegistry::SignatureVersion do
    let(:version) do
      DSPy::Registry::SignatureRegistry::SignatureVersion.new(
        signature_name: "TestSignature",
        version: "v1.0.0",
        configuration: test_configuration,
        metadata: test_metadata,
        performance_score: 0.85
      )
    end

    describe '#initialize' do
      it 'creates a signature version with all attributes' do
        expect(version.signature_name).to eq("TestSignature")
        expect(version.version).to eq("v1.0.0")
        expect(version.configuration).to eq(test_configuration)
        expect(version.performance_score).to eq(0.85)
        expect(version.is_deployed).to be(false)
        expect(version.version_hash).to be_a(String)
        expect(version.version_hash.length).to eq(12)
      end

      it 'freezes configuration and metadata' do
        expect(version.configuration).to be_frozen
        expect(version.metadata).to be_frozen
      end

      it 'includes registry metadata' do
        expect(version.metadata[:registry_version]).to eq("1.0")
        expect(version.metadata[:created_at]).to be_a(String)
      end
    end

    describe '#to_h and #from_h' do
      it 'serializes and deserializes correctly' do
        hash = version.to_h
        restored = DSPy::Registry::SignatureRegistry::SignatureVersion.from_h(hash)
        
        expect(restored.signature_name).to eq(version.signature_name)
        expect(restored.version).to eq(version.version)
        expect(restored.configuration).to eq(version.configuration)
        expect(restored.performance_score).to eq(version.performance_score)
        expect(restored.is_deployed).to eq(version.is_deployed)
      end
    end

    describe '#with_performance_score' do
      it 'returns new version with updated score' do
        updated = version.with_performance_score(0.95)
        
        expect(updated.performance_score).to eq(0.95)
        expect(updated.version).to eq(version.version)
        expect(version.performance_score).to eq(0.85) # Original unchanged
      end
    end

    describe '#deploy and #undeploy' do
      it 'returns new version with deployment status' do
        deployed = version.deploy
        expect(deployed.is_deployed).to be(true)
        expect(version.is_deployed).to be(false) # Original unchanged
        
        undeployed = deployed.undeploy
        expect(undeployed.is_deployed).to be(false)
      end
    end
  end

  describe '#initialize' do
    it 'creates registry directory structure' do
      registry # Trigger registry creation
      
      expect(Dir.exist?(temp_dir)).to be(true)
      expect(Dir.exist?(File.join(temp_dir, "signatures"))).to be(true)
      expect(Dir.exist?(File.join(temp_dir, "backups"))).to be(true)
    end

    it 'creates or loads configuration file' do
      registry # Trigger registry creation
      
      config_file = File.join(temp_dir, "registry.yml")
      expect(File.exist?(config_file)).to be(true)
      
      config_data = YAML.load_file(config_file, symbolize_names: true)
      expect(config_data[:auto_version]).to be(true)
    end
  end

  describe '#register_version' do
    it 'registers a new signature version' do
      version = registry.register_version(
        "TestSignature",
        test_configuration,
        metadata: test_metadata
      )
      
      expect(version).to be_a(DSPy::Registry::SignatureRegistry::SignatureVersion)
      expect(version.signature_name).to eq("TestSignature")
      expect(version.configuration).to eq(test_configuration)
    end

    it 'auto-generates version when auto_version is enabled' do
      version = registry.register_version(
        "TestSignature",
        test_configuration
      )
      
      expect(version.version).to match(/^v\d{8}_\d{6}$/) # timestamp format
    end

    it 'uses provided version when specified' do
      version = registry.register_version(
        "TestSignature",
        test_configuration,
        version: "custom_v1.0"
      )
      
      expect(version.version).to eq("custom_v1.0")
    end

    it 'prevents duplicate versions' do
      registry.register_version(
        "TestSignature",
        test_configuration,
        version: "v1.0.0"
      )
      
      expect {
        registry.register_version(
          "TestSignature",
          test_configuration,
          version: "v1.0.0"
        )
      }.to raise_error(ArgumentError, /Version v1.0.0 already exists/)
    end

    it 'limits versions per signature when configured' do
      config.max_versions_per_signature = 2
      
      # Register 3 versions
      3.times do |i|
        registry.register_version(
          "TestSignature",
          test_configuration,
          version: "v1.#{i}"
        )
      end
      
      versions = registry.list_versions("TestSignature")
      expect(versions.size).to eq(2) # Only keeps the latest 2
      expect(versions.map(&:version)).to include("v1.1", "v1.2")
    end

  end

  describe '#deploy_version' do
    let!(:version1) do
      registry.register_version(
        "TestSignature",
        test_configuration,
        version: "v1.0",
        metadata: test_metadata
      )
    end
    
    let!(:version2) do
      registry.register_version(
        "TestSignature",
        test_configuration.merge(instruction: "Updated instruction"),
        version: "v2.0",
        metadata: test_metadata
      )
    end

    it 'deploys specified version' do
      deployed = registry.deploy_version("TestSignature", "v1.0")
      
      expect(deployed).not_to be_nil
      expect(deployed.version).to eq("v1.0")
      expect(deployed.is_deployed).to be(true)
    end

    it 'undeploys other versions when deploying' do
      registry.deploy_version("TestSignature", "v1.0")
      registry.deploy_version("TestSignature", "v2.0")
      
      versions = registry.list_versions("TestSignature")
      deployed_versions = versions.select(&:is_deployed)
      
      expect(deployed_versions.size).to eq(1)
      expect(deployed_versions.first.version).to eq("v2.0")
    end

    it 'returns nil for non-existent version' do
      result = registry.deploy_version("TestSignature", "v99.0")
      expect(result).to be_nil
    end

  end

  describe '#rollback' do
    before do
      # Create versions
      registry.register_version("TestSignature", test_configuration, version: "v1.0")
      registry.register_version("TestSignature", test_configuration, version: "v2.0")
      registry.register_version("TestSignature", test_configuration, version: "v3.0")
      
      # Deploy v2.0, then v3.0
      registry.deploy_version("TestSignature", "v2.0")
      registry.deploy_version("TestSignature", "v3.0")
    end

    it 'rolls back to previous deployed version' do
      rolled_back = registry.rollback("TestSignature")
      
      expect(rolled_back).not_to be_nil
      expect(rolled_back.version).to eq("v2.0")
      expect(rolled_back.is_deployed).to be(true)
    end

    it 'returns nil when no previous version to rollback to' do
      # Clear deployment history by creating new signature
      registry.register_version("NewSignature", test_configuration, version: "v1.0")
      registry.deploy_version("NewSignature", "v1.0")
      
      result = registry.rollback("NewSignature")
      expect(result).to be_nil
    end

  end

  describe '#get_deployed_version' do
    it 'returns currently deployed version' do
      registry.register_version("TestSignature", test_configuration, version: "v1.0")
      registry.deploy_version("TestSignature", "v1.0")
      
      deployed = registry.get_deployed_version("TestSignature")
      expect(deployed.version).to eq("v1.0")
      expect(deployed.is_deployed).to be(true)
    end

    it 'returns nil when no version is deployed' do
      registry.register_version("TestSignature", test_configuration, version: "v1.0")
      
      deployed = registry.get_deployed_version("TestSignature")
      expect(deployed).to be_nil
    end
  end

  describe '#list_versions' do
    it 'returns empty array for non-existent signature' do
      versions = registry.list_versions("NonExistent")
      expect(versions).to eq([])
    end

    it 'returns all versions for a signature' do
      registry.register_version("TestSignature", test_configuration, version: "v1.0")
      registry.register_version("TestSignature", test_configuration, version: "v2.0")
      
      versions = registry.list_versions("TestSignature")
      expect(versions.size).to eq(2)
      expect(versions.map(&:version)).to include("v1.0", "v2.0")
    end
  end

  describe '#list_signatures' do
    it 'returns empty array when no signatures registered' do
      signatures = registry.list_signatures
      expect(signatures).to eq([])
    end

    it 'returns all registered signature names' do
      registry.register_version("Signature1", test_configuration)
      registry.register_version("Signature2", test_configuration)
      
      signatures = registry.list_signatures
      expect(signatures).to include("Signature1", "Signature2")
    end
  end

  describe '#update_performance_score' do
    let!(:version) do
      registry.register_version(
        "TestSignature",
        test_configuration,
        version: "v1.0"
      )
    end

    it 'updates performance score for existing version' do
      updated = registry.update_performance_score("TestSignature", "v1.0", 0.92)
      
      expect(updated).not_to be_nil
      expect(updated.performance_score).to eq(0.92)
    end

    it 'returns nil for non-existent version' do
      result = registry.update_performance_score("TestSignature", "v99.0", 0.92)
      expect(result).to be_nil
    end

  end

  describe '#get_performance_history' do
    before do
      registry.register_version("TestSignature", test_configuration, version: "v1.0")
      registry.register_version("TestSignature", test_configuration, version: "v2.0")
      registry.update_performance_score("TestSignature", "v1.0", 0.8)
      registry.update_performance_score("TestSignature", "v2.0", 0.9)
    end

    it 'returns performance history with trends' do
      history = registry.get_performance_history("TestSignature")
      
      expect(history[:versions].size).to eq(2)
      expect(history[:trends][:latest_score]).to eq(0.9)
      expect(history[:trends][:best_score]).to eq(0.9)
      expect(history[:trends][:worst_score]).to eq(0.8)
    end

    it 'returns empty history for signature with no scores' do
      registry.register_version("NoScoreSignature", test_configuration)
      
      history = registry.get_performance_history("NoScoreSignature")
      expect(history[:versions]).to eq([])
      expect(history[:trends]).to eq({})
    end
  end

  describe '#compare_versions' do
    before do
      registry.register_version("TestSignature", test_configuration, version: "v1.0")
      registry.register_version(
        "TestSignature", 
        test_configuration.merge(instruction: "Updated instruction"), 
        version: "v2.0"
      )
      registry.update_performance_score("TestSignature", "v1.0", 0.8)
      registry.update_performance_score("TestSignature", "v2.0", 0.9)
    end

    it 'compares two versions with detailed analysis' do
      comparison = registry.compare_versions("TestSignature", "v1.0", "v2.0")
      
      expect(comparison).not_to be_nil
      expect(comparison[:version_1][:version]).to eq("v1.0")
      expect(comparison[:version_2][:version]).to eq("v2.0")
      expect(comparison[:comparison][:performance_difference]).to be_within(0.001).of(-0.1) # v1.0 - v2.0
      expect(comparison[:comparison][:configuration_changes]).to be_an(Array)
    end

    it 'returns nil when one version does not exist' do
      result = registry.compare_versions("TestSignature", "v1.0", "v99.0")
      expect(result).to be_nil
    end
  end

  describe '#export_registry and #import_registry' do
    let(:export_file) { File.join(temp_dir, 'export.yml') }

    before do
      registry.register_version("Signature1", test_configuration, version: "v1.0")
      registry.register_version("Signature2", test_configuration, version: "v1.0")
      registry.deploy_version("Signature1", "v1.0")
    end

    it 'exports entire registry state' do
      registry.export_registry(export_file)
      
      expect(File.exist?(export_file)).to be(true)
      
      data = YAML.load_file(export_file, symbolize_names: true)
      expect(data[:signatures]).to have_key(:Signature1)
      expect(data[:signatures]).to have_key(:Signature2)
      expect(data[:exported_at]).to be_a(String)
    end

    it 'imports registry state' do
      registry.export_registry(export_file)
      
      # Create new registry and import
      new_registry = DSPy::Registry::SignatureRegistry.new(config: config)
      new_registry.import_registry(export_file)
      
      signatures = new_registry.list_signatures
      expect(signatures).to include("Signature1", "Signature2")
      
      deployed = new_registry.get_deployed_version("Signature1")
      expect(deployed.version).to eq("v1.0")
    end

  end
end