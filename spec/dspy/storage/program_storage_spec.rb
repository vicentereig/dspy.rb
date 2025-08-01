require 'spec_helper'
require 'tempfile'
require 'tmpdir'
require 'dspy/storage/program_storage'

RSpec.describe DSPy::Storage::ProgramStorage do
  let(:temp_dir) { Dir.mktmpdir }
  let(:storage) { DSPy::Storage::ProgramStorage.new(storage_path: temp_dir) }
  
  let(:mock_program) do
    double('Program', 
      class: double(name: 'MockProgram'),
      signature_class: double(name: 'MockSignature'),
      prompt: double(instruction: 'Test instruction'),
      few_shot_examples: []
    )
  end
  
  let(:mock_optimization_result) do
    {
      best_score_value: 0.85,
      best_score_name: 'accuracy',
      scores: { accuracy: 0.85 },
      history: { total_trials: 5 },
      metadata: { optimizer: 'TestOptimizer' }
    }
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe '#initialize' do
    it 'creates storage directory if it does not exist' do
      non_existent_dir = File.join(temp_dir, 'new_storage')
      storage = DSPy::Storage::ProgramStorage.new(storage_path: non_existent_dir)
      
      expect(Dir.exist?(non_existent_dir)).to be(true)
      expect(Dir.exist?(File.join(non_existent_dir, 'programs'))).to be(true)
    end

    it 'does not create directory when create_directories is false' do
      non_existent_dir = File.join(temp_dir, 'no_create')
      storage = DSPy::Storage::ProgramStorage.new(
        storage_path: non_existent_dir, 
        create_directories: false
      )
      
      expect(Dir.exist?(non_existent_dir)).to be(false)
    end
  end

  describe '#save_program' do
    it 'saves a program with optimization results' do
      saved_program = storage.save_program(mock_program, mock_optimization_result)
      
      expect(saved_program).to be_a(DSPy::Storage::ProgramStorage::SavedProgram)
      expect(saved_program.program).to eq(mock_program)
      expect(saved_program.optimization_result).to eq(mock_optimization_result)
      expect(saved_program.program_id).to be_a(String)
      expect(saved_program.program_id.length).to eq(16)
    end

    it 'saves program data to file' do
      saved_program = storage.save_program(mock_program, mock_optimization_result)
      
      file_path = File.join(temp_dir, 'programs', "#{saved_program.program_id}.json")
      expect(File.exist?(file_path)).to be(true)
      
      data = JSON.parse(File.read(file_path), symbolize_names: true)
      expect(data[:program_id]).to eq(saved_program.program_id)
      expect(data[:optimization_result]).to eq(mock_optimization_result)
    end

    it 'updates history when saving' do
      storage.save_program(mock_program, mock_optimization_result)
      
      history_path = File.join(temp_dir, 'history.json')
      expect(File.exist?(history_path)).to be(true)
      
      history = JSON.parse(File.read(history_path), symbolize_names: true)
      expect(history[:programs].size).to eq(1)
      expect(history[:summary][:total_programs]).to eq(1)
      expect(history[:summary][:avg_score]).to eq(0.85)
    end

    it 'emits save events' do
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.save_start', 
        hash_including(:storage_path)
      )
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.save_complete', 
        hash_including(:program_id, :best_score)
      )
      
      storage.save_program(mock_program, mock_optimization_result)
    end
  end

  describe '#load_program' do
    let(:saved_program) { storage.save_program(mock_program, mock_optimization_result) }

    it 'loads a saved program by ID' do
      loaded_program = storage.load_program(saved_program.program_id)
      
      expect(loaded_program).to be_a(DSPy::Storage::ProgramStorage::SavedProgram)
      expect(loaded_program.program_id).to eq(saved_program.program_id)
      expect(loaded_program.optimization_result).to eq(mock_optimization_result)
    end

    it 'returns nil for non-existent program' do
      result = storage.load_program('non_existent_id')
      expect(result).to be_nil
    end

    it 'emits load events' do
      # Allow save events first (from saved_program creation)
      allow(DSPy::Instrumentation).to receive(:emit).and_call_original
      
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.load_start',
        hash_including(:program_id)
      ).and_call_original
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.load_complete',
        hash_including(:program_id, :age_hours)
      ).and_call_original
      
      storage.load_program(saved_program.program_id)
    end

    it 'emits error event for missing program' do
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.load_start',
        hash_including(:program_id)
      )
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.load_error',
        hash_including(:program_id, :error)
      )
      
      storage.load_program('missing_id')
    end
  end

  describe '#list_programs' do
    it 'returns empty array when no programs saved' do
      expect(storage.list_programs).to eq([])
    end

    it 'returns list of saved programs' do
      saved1 = storage.save_program(mock_program, mock_optimization_result)
      saved2 = storage.save_program(mock_program, mock_optimization_result.merge(best_score_value: 0.9))
      
      programs = storage.list_programs
      expect(programs.size).to eq(2)
      
      program_ids = programs.map { |p| p[:program_id] }
      expect(program_ids).to include(saved1.program_id, saved2.program_id)
    end
  end

  describe '#get_history' do
    it 'returns empty history when no programs saved' do
      history = storage.get_history
      expect(history[:programs]).to eq([])
      expect(history[:summary]).to eq({})
    end

    it 'returns comprehensive history with multiple programs' do
      3.times do |i|
        storage.save_program(mock_program, mock_optimization_result.merge(best_score_value: 0.7 + i * 0.1))
      end
      
      history = storage.get_history
      expect(history[:programs].size).to eq(3)
      expect(history[:summary][:total_programs]).to eq(3)
      expect(history[:summary][:avg_score]).to be_within(0.001).of(0.8) # (0.7 + 0.8 + 0.9) / 3
    end
  end

  describe '#delete_program' do
    let(:saved_program) { storage.save_program(mock_program, mock_optimization_result) }

    it 'deletes existing program' do
      result = storage.delete_program(saved_program.program_id)
      expect(result).to be(true)
      
      file_path = File.join(temp_dir, 'programs', "#{saved_program.program_id}.json")
      expect(File.exist?(file_path)).to be(false)
    end

    it 'returns false for non-existent program' do
      result = storage.delete_program('non_existent_id')
      expect(result).to be(false)
    end

    it 'removes program from history' do
      storage.delete_program(saved_program.program_id)
      
      programs = storage.list_programs
      program_ids = programs.map { |p| p[:program_id] }
      expect(program_ids).not_to include(saved_program.program_id)
    end

    it 'emits delete event' do
      # Allow save events first (from saved_program creation)
      allow(DSPy::Instrumentation).to receive(:emit).and_call_original
      
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.delete',
        hash_including(:program_id)
      ).and_call_original
      
      storage.delete_program(saved_program.program_id)
    end
  end

  describe '#export_programs' do
    let(:temp_export_file) { File.join(temp_dir, 'export.json') }
    
    it 'exports multiple programs to file' do
      saved1 = storage.save_program(mock_program, mock_optimization_result)
      saved2 = storage.save_program(mock_program, mock_optimization_result.merge(best_score_value: 0.9))
      
      storage.export_programs([saved1.program_id, saved2.program_id], temp_export_file)
      
      expect(File.exist?(temp_export_file)).to be(true)
      
      export_data = JSON.parse(File.read(temp_export_file), symbolize_names: true)
      expect(export_data[:programs].size).to eq(2)
      expect(export_data[:exported_at]).to be_a(String)
    end

    it 'emits export event' do
      saved = storage.save_program(mock_program, mock_optimization_result)
      
      # Allow all other events
      allow(DSPy::Instrumentation).to receive(:emit).and_call_original
      
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.export',
        hash_including(:export_path, :program_count)
      ).and_call_original
      
      storage.export_programs([saved.program_id], temp_export_file)
    end
  end

  describe '#import_programs' do
    let(:temp_export_file) { File.join(temp_dir, 'export.json') }
    
    it 'imports programs from exported file' do
      # First export some programs
      saved = storage.save_program(mock_program, mock_optimization_result)
      storage.export_programs([saved.program_id], temp_export_file)
      
      # Clear storage
      storage.delete_program(saved.program_id)
      expect(storage.list_programs).to be_empty
      
      # Import back
      imported = storage.import_programs(temp_export_file)
      
      expect(imported.size).to eq(1)
      expect(imported.first.program_id).to eq(saved.program_id)
      expect(storage.list_programs.size).to eq(1)
    end

    it 'emits import event' do
      saved = storage.save_program(mock_program, mock_optimization_result)
      storage.export_programs([saved.program_id], temp_export_file)
      
      expect(DSPy::Instrumentation).to receive(:emit).with(
        'dspy.storage.import',
        hash_including(:import_path, :program_count)
      )
      
      storage.import_programs(temp_export_file)
    end
  end

  describe DSPy::Storage::ProgramStorage::SavedProgram do
    describe '#initialize' do
      it 'generates program ID if not provided' do
        saved_program = DSPy::Storage::ProgramStorage::SavedProgram.new(
          program: mock_program,
          optimization_result: mock_optimization_result
        )
        
        expect(saved_program.program_id).to be_a(String)
        expect(saved_program.program_id.length).to eq(16)
      end

      it 'uses provided program ID' do
        custom_id = 'custom_test_id'
        saved_program = DSPy::Storage::ProgramStorage::SavedProgram.new(
          program: mock_program,
          optimization_result: mock_optimization_result,
          program_id: custom_id
        )
        
        expect(saved_program.program_id).to eq(custom_id)
      end

      it 'includes version metadata' do
        saved_program = DSPy::Storage::ProgramStorage::SavedProgram.new(
          program: mock_program,
          optimization_result: mock_optimization_result
        )
        
        expect(saved_program.metadata[:ruby_version]).to eq(RUBY_VERSION)
        expect(saved_program.metadata[:saved_with]).to eq("DSPy::Storage::ProgramStorage")
      end
    end

    describe '#to_h and #from_h' do
      it 'serializes and deserializes correctly' do
        original = DSPy::Storage::ProgramStorage::SavedProgram.new(
          program: mock_program,
          optimization_result: mock_optimization_result,
          metadata: { test: 'value' }
        )
        
        hash_data = original.to_h
        restored = DSPy::Storage::ProgramStorage::SavedProgram.from_h(hash_data)
        
        expect(restored.program_id).to eq(original.program_id)
        expect(restored.optimization_result).to eq(original.optimization_result)
        expect(restored.saved_at.to_i).to eq(original.saved_at.to_i) # Compare as integers to avoid precision issues
      end
    end
  end
end