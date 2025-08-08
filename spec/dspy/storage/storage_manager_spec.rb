require 'spec_helper'
require 'tempfile'
require 'tmpdir'
require 'dspy/storage/storage_manager'

RSpec.describe DSPy::Storage::StorageManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config) do
    config = DSPy::Storage::StorageManager::StorageConfig.new
    config.storage_path = temp_dir
    config.auto_save = true
    config
  end
  let(:storage_manager) { DSPy::Storage::StorageManager.new(config: config) }
  
  let(:mock_program) do
    double('Program', 
      class: double(name: 'MockProgram'),
      signature_class: double(name: 'MockSignature'),
      prompt: double(instruction: 'Test instruction'),
      few_shot_examples: []
    )
  end
  
  let(:mock_optimization_result) do
    double('OptimizationResult',
      optimized_program: mock_program,
      best_score_value: 0.85,
      best_score_name: 'accuracy',
      scores: { accuracy: 0.85 },
      history: { total_trials: 5 },
      metadata: { optimizer: 'TestOptimizer', optimization_timestamp: Time.now.iso8601 },
      class: double(name: 'MockOptimizationResult'),
      to_h: {
        optimized_program: mock_program,
        best_score_value: 0.85,
        best_score_name: 'accuracy',
        scores: { accuracy: 0.85 },
        history: { total_trials: 5 },
        metadata: { optimizer: 'TestOptimizer' }
      }
    )
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe DSPy::Storage::StorageManager::StorageConfig do
    describe '#initialize' do
      it 'sets sensible defaults' do
        config = DSPy::Storage::StorageManager::StorageConfig.new
        
        expect(config.storage_path).to eq("./dspy_storage")
        expect(config.auto_save).to be(true)
        expect(config.save_intermediate_results).to be(false)
        expect(config.max_stored_programs).to eq(100)
        expect(config.compress_old_programs).to be(false)
      end
    end

    describe '#to_h' do
      it 'serializes configuration to hash' do
        config = DSPy::Storage::StorageManager::StorageConfig.new
        config.auto_save = false
        config.max_stored_programs = 50
        
        hash = config.to_h
        expect(hash[:auto_save]).to be(false)
        expect(hash[:max_stored_programs]).to eq(50)
      end
    end
  end

  describe '#initialize' do
    it 'creates storage manager with default config' do
      manager = DSPy::Storage::StorageManager.new
      
      expect(manager.config).to be_a(DSPy::Storage::StorageManager::StorageConfig)
      expect(manager.storage).to be_a(DSPy::Storage::ProgramStorage)
    end

    it 'creates storage manager with custom config' do
      custom_config = DSPy::Storage::StorageManager::StorageConfig.new
      custom_config.auto_save = false
      
      manager = DSPy::Storage::StorageManager.new(config: custom_config)
      expect(manager.config.auto_save).to be(false)
    end
  end

  describe '#save_optimization_result' do
    it 'saves optimization result with auto_save enabled' do
      result = storage_manager.save_optimization_result(
        mock_optimization_result,
        tags: ['test'],
        description: 'Test optimization'
      )
      
      expect(result).to be_a(DSPy::Storage::ProgramStorage::SavedProgram)
      expect(result.metadata[:tags]).to include('test')
      expect(result.metadata[:description]).to eq('Test optimization')
    end

    it 'does not save when auto_save is disabled' do
      config.auto_save = false
      
      result = storage_manager.save_optimization_result(mock_optimization_result)
      expect(result).to be_nil
    end

    it 'does not save when optimization result has no program' do
      result_without_program = double('BadOptimizationResult', optimized_program: nil)
      
      result = storage_manager.save_optimization_result(result_without_program)
      expect(result).to be_nil
    end

    it 'includes enhanced metadata' do
      result = storage_manager.save_optimization_result(
        mock_optimization_result,
        tags: ['mipro'],
        description: 'MIPROv2 optimization'
      )
      
      expect(result.metadata[:optimizer_class]).to eq('MockOptimizationResult')
      expect(result.metadata[:saved_by]).to eq('StorageManager')
      expect(result.metadata[:tags]).to include('mipro')
    end
  end

  describe '#find_programs' do
    before do
      # Save multiple programs with different characteristics
      storage_manager.save_optimization_result(
        mock_optimization_result,
        tags: ['mipro', 'test'],
        metadata: { signature_class: 'QASignature' }
      )
      
      high_score_result = double('HighScoreResult',
        optimized_program: mock_program,
        best_score_value: 0.95,
        metadata: { optimizer: 'SimpleOptimizer' },
        class: double(name: 'SimpleOptimizerResult'),
        to_h: { best_score_value: 0.95, metadata: { optimizer: 'SimpleOptimizer' } }
      )
      
      storage_manager.save_optimization_result(
        high_score_result,
        tags: ['simple'],
        metadata: { signature_class: 'ClassifySignature' }
      )
    end

    it 'finds programs by optimizer' do
      programs = storage_manager.find_programs(optimizer: 'SimpleOptimizer')
      expect(programs.size).to eq(1)
      expect(programs.first[:optimizer]).to eq('SimpleOptimizer')
    end

    it 'finds programs by minimum score' do
      programs = storage_manager.find_programs(min_score: 0.9)
      expect(programs.size).to eq(1)
      expect(programs.first[:best_score]).to eq(0.95)
    end

    it 'finds programs by tags' do
      programs = storage_manager.find_programs(tags: ['mipro'])
      expect(programs.size).to eq(1)
    end

    it 'finds programs by signature class' do
      programs = storage_manager.find_programs(signature_class: 'QASignature')
      expect(programs.size).to eq(1)
    end

    it 'filters by age in days' do
      programs = storage_manager.find_programs(max_age_days: 1)
      expect(programs.size).to eq(2) # Both saved today
      
      programs = storage_manager.find_programs(max_age_days: 0)
      expect(programs.size).to eq(0) # None saved more than 0 days ago
    end
  end

  describe '#get_best_program' do
    before do
      # Save programs with different scores for same signature
      storage_manager.save_optimization_result(
        mock_optimization_result, # score: 0.85
        metadata: { signature_class: 'QASignature' }
      )
      
      better_result = double('BetterResult',
        optimized_program: mock_program,
        best_score_value: 0.95,
        metadata: {},
        class: double(name: 'BetterResult'),
        to_h: { best_score_value: 0.95, metadata: {} }
      )
      
      storage_manager.save_optimization_result(
        better_result,
        metadata: { signature_class: 'QASignature' }
      )
    end

    it 'returns the highest scoring program for signature class' do
      best = storage_manager.get_best_program('QASignature')
      
      expect(best).to be_a(DSPy::Storage::ProgramStorage::SavedProgram)
      expect(best.optimization_result[:best_score_value]).to eq(0.95)
    end

    it 'returns nil for non-existent signature class' do
      result = storage_manager.get_best_program('NonExistentSignature')
      expect(result).to be_nil
    end
  end

  describe '#create_checkpoint' do
    it 'creates a checkpoint with special metadata' do
      checkpoint = storage_manager.create_checkpoint(
        mock_optimization_result,
        'before_heavy_optimization',
        metadata: { experiment: 'test' }
      )
      
      expect(checkpoint).to be_a(DSPy::Storage::ProgramStorage::SavedProgram)
      expect(checkpoint.metadata[:checkpoint]).to be(true)
      expect(checkpoint.metadata[:checkpoint_name]).to eq('before_heavy_optimization')
      expect(checkpoint.metadata[:tags]).to include('checkpoint')
    end
  end

  describe '#restore_checkpoint' do
    before do
      storage_manager.create_checkpoint(
        mock_optimization_result,
        'test_checkpoint'
      )
    end

    it 'restores from checkpoint by name' do
      restored = storage_manager.restore_checkpoint('test_checkpoint')
      
      expect(restored).to be_a(DSPy::Storage::ProgramStorage::SavedProgram)
      expect(restored.metadata[:checkpoint_name]).to eq('test_checkpoint')
    end

    it 'returns nil for non-existent checkpoint' do
      result = storage_manager.restore_checkpoint('non_existent')
      expect(result).to be_nil
    end
  end

  describe '#get_optimization_history' do
    before do
      # Save programs with different optimizers and times
      3.times do |i|
        result = double("Result#{i}",
          optimized_program: mock_program,
          best_score_value: 0.7 + i * 0.1,
          metadata: { optimizer: i.even? ? 'MIPROv2' : 'SimpleOptimizer' },
          class: double(name: "Result#{i}"),
          to_h: { best_score_value: 0.7 + i * 0.1, metadata: { optimizer: i.even? ? 'MIPROv2' : 'SimpleOptimizer' } }
        )
        
        storage_manager.save_optimization_result(result)
        sleep(0.01) # Ensure different timestamps
      end
    end

    it 'returns comprehensive optimization history with trends' do
      history = storage_manager.get_optimization_history
      
      expect(history[:programs].size).to eq(3)
      expect(history[:summary][:total_programs]).to eq(3)
      expect(history[:optimizer_stats]).to have_key('MIPROv2')
      expect(history[:optimizer_stats]).to have_key('SimpleOptimizer')
      expect(history[:trends]).to have_key(:improvement_percentage)
    end

    it 'calculates optimizer statistics correctly' do
      history = storage_manager.get_optimization_history
      
      mipro_stats = history[:optimizer_stats]['MIPROv2']
      expect(mipro_stats[:count]).to eq(2) # Programs 0 and 2 (even indices)
      expect(mipro_stats[:avg_score]).to be_within(0.01).of(0.8) # (0.7 + 0.9) / 2
      expect(mipro_stats[:best_score]).to be_within(0.001).of(0.9)
    end
  end

  describe '#cleanup_old_programs' do
    before do
      config.max_stored_programs = 2
      
      # Save 3 programs with different scores
      3.times do |i|
        result = double("Result#{i}",
          optimized_program: mock_program,
          best_score_value: 0.5 + i * 0.2, # 0.5, 0.7, 0.9
          metadata: {},
          class: double(name: "Result#{i}"),
          to_h: { best_score_value: 0.5 + i * 0.2, metadata: {} }
        )
        
        storage_manager.save_optimization_result(result)
        sleep(0.01) # Ensure different timestamps
      end
    end

    it 'deletes lowest scoring programs' do
      expect(storage_manager.storage.list_programs.size).to eq(3)
      
      deleted_count = storage_manager.cleanup_old_programs
      
      expect(deleted_count).to eq(1)
      expect(storage_manager.storage.list_programs.size).to eq(2)
      
      # Should keep the two highest scoring programs
      remaining_scores = storage_manager.storage.list_programs.map { |p| p[:best_score] }.sort
      expect(remaining_scores).to eq([0.7, 0.9])
    end

  end

  describe '#compare_programs' do
    let(:program1_id) { storage_manager.save_optimization_result(mock_optimization_result).program_id }
    let(:program2_result) do
      double('Result2',
        optimized_program: mock_program,
        best_score_value: 0.75,
        metadata: { optimizer: 'SimpleOptimizer' },
        class: double(name: 'Result2'),
        to_h: { best_score_value: 0.75, metadata: { optimizer: 'SimpleOptimizer' } }
      )
    end
    let(:program2_id) { storage_manager.save_optimization_result(program2_result).program_id }

    it 'compares two programs and returns detailed comparison' do
      comparison = storage_manager.compare_programs(program1_id, program2_id)
      
      expect(comparison).to have_key(:program_1)
      expect(comparison).to have_key(:program_2) 
      expect(comparison).to have_key(:comparison)
      
      expect(comparison[:comparison][:score_difference]).to be_within(0.001).of(0.1) # 0.85 - 0.75
      expect(comparison[:comparison][:better_program]).to eq(program1_id)
    end

    it 'returns nil when one program does not exist' do
      result = storage_manager.compare_programs(program1_id, 'non_existent_id')
      expect(result).to be_nil
    end
  end

  describe 'class methods' do
    describe '.instance' do
      it 'returns singleton instance' do
        instance1 = DSPy::Storage::StorageManager.instance
        instance2 = DSPy::Storage::StorageManager.instance
        
        expect(instance1).to be(instance2)
      end
    end

    describe '.configure' do
      it 'configures global instance' do
        custom_config = DSPy::Storage::StorageManager::StorageConfig.new
        custom_config.auto_save = false
        
        DSPy::Storage::StorageManager.configure(custom_config)
        
        expect(DSPy::Storage::StorageManager.instance.config.auto_save).to be(false)
      end
    end

    describe '.save' do
      it 'saves using global instance' do
        allow(DSPy::Storage::StorageManager.instance).to receive(:save_optimization_result)
          .with(mock_optimization_result, metadata: {})
          .and_return(nil)
        
        result = DSPy::Storage::StorageManager.save(mock_optimization_result)
        expect(result).to be_nil
      end
    end

    describe '.load' do
      it 'loads using global instance' do
        test_id = 'test_id'
        allow(DSPy::Storage::StorageManager.instance.storage).to receive(:load_program)
          .with(test_id)
          .and_return(nil)
        
        result = DSPy::Storage::StorageManager.load(test_id)
        expect(result).to be_nil
      end
    end

    describe '.best' do
      it 'finds best program using global instance' do
        signature_class = 'TestSignature'
        allow(DSPy::Storage::StorageManager.instance).to receive(:get_best_program)
          .with(signature_class)
          .and_return(nil)
        
        result = DSPy::Storage::StorageManager.best(signature_class)
        expect(result).to be_nil
      end
    end
  end
end