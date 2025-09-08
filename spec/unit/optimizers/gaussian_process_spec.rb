# typed: false

require 'spec_helper'
require_relative '../../../lib/dspy/optimizers/gaussian_process'

RSpec.describe DSPy::Optimizers::GaussianProcess do
  describe '#initialize' do
    it 'creates a Gaussian Process with default parameters' do
      gp = DSPy::Optimizers::GaussianProcess.new
      expect(gp).to be_a(DSPy::Optimizers::GaussianProcess)
    end

    it 'accepts custom kernel parameters' do
      gp = DSPy::Optimizers::GaussianProcess.new(length_scale: 2.0, signal_variance: 0.5, noise_variance: 0.01)
      expect(gp).to be_a(DSPy::Optimizers::GaussianProcess)
    end
  end

  describe '#rbf_kernel' do
    let(:gp) { DSPy::Optimizers::GaussianProcess.new }

    it 'computes RBF kernel for identical points' do
      x1 = [[1.0], [2.0]]
      x2 = [[1.0], [2.0]]
      
      kernel_matrix = gp.rbf_kernel(x1, x2)
      
      # Identical points should have kernel value = signal_variance (default 1.0)
      expect(kernel_matrix[0, 0]).to be_within(1e-6).of(1.0)
      expect(kernel_matrix[1, 1]).to be_within(1e-6).of(1.0)
    end

    it 'computes smaller values for distant points' do
      x1 = [[0.0]]
      x2 = [[5.0]]  # Far apart with default length_scale=1.0
      
      kernel_matrix = gp.rbf_kernel(x1, x2)
      
      # Should be much smaller than 1.0
      expect(kernel_matrix[0, 0]).to be < 0.01
    end
  end

  describe '#fit' do
    let(:gp) { DSPy::Optimizers::GaussianProcess.new(noise_variance: 0.1) }

    it 'fits GP to simple training data' do
      x_train = [[1.0], [2.0], [3.0]]
      y_train = [1.0, 4.0, 9.0]  # Simple quadratic pattern
      
      expect { gp.fit(x_train, y_train) }.not_to raise_error
    end

    it 'stores training data' do
      x_train = [[1.0], [2.0]]
      y_train = [1.0, 4.0]
      
      gp.fit(x_train, y_train)
      
      expect(gp.instance_variable_get(:@fitted)).to be true
    end
  end

  describe '#predict' do
    let(:gp) { DSPy::Optimizers::GaussianProcess.new(noise_variance: 0.01) }

    context 'when fitted' do
      before do
        # Fit to simple linear function: y = 2x
        x_train = [[1.0], [2.0], [3.0]]
        y_train = [2.0, 4.0, 6.0]
        gp.fit(x_train, y_train)
      end

      it 'predicts mean values' do
        x_test = [[1.5], [2.5]]
        
        means = gp.predict(x_test)
        
        expect(means.size).to eq(2)
        # Should predict close to 3.0 and 5.0 for linear function
        expect(means[0]).to be_within(0.5).of(3.0)
        expect(means[1]).to be_within(0.5).of(5.0)
      end

      it 'predicts with uncertainty' do
        x_test = [[1.5]]
        
        means, stds = gp.predict(x_test, return_std: true)
        
        expect(means.size).to eq(1)
        expect(stds.size).to eq(1)
        expect(stds[0]).to be > 0  # Should have some uncertainty
      end

      it 'has low uncertainty at training points' do
        x_test = [[2.0]]  # Exact training point
        
        means, stds = gp.predict(x_test, return_std: true)
        
        expect(stds[0]).to be < 0.1  # Should be very certain
      end
    end

    context 'when not fitted' do
      it 'raises an error' do
        x_test = [[1.0]]
        
        expect { gp.predict(x_test) }.to raise_error(/not fitted/)
      end
    end
  end
end