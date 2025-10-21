# typed: false

require 'spec_helper'

miprov2_available = begin
  require 'dspy/miprov2'
  true
rescue LoadError
  false
end

if miprov2_available
  RSpec.describe DSPy::Optimizers::GaussianProcess, :miprov2 do
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

    describe '#fit' do
      let(:gp) { DSPy::Optimizers::GaussianProcess.new(noise_variance: 0.1) }

      it 'fits GP to simple training data' do
        x_train = [[1.0], [2.0], [3.0]]
        y_train = [1.0, 4.0, 9.0]

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
          x_train = [[1.0], [2.0], [3.0]]
          y_train = [2.0, 4.0, 6.0]
          gp.fit(x_train, y_train)
        end

        it 'predicts mean values' do
          x_test = [[1.5], [2.5]]

          means = gp.predict(x_test)

          expect(means.size).to eq(2)
          expect(means[0]).to be_within(0.5).of(3.0)
          expect(means[1]).to be_within(0.5).of(5.0)
        end

        it 'predicts with uncertainty' do
          x_test = [[1.5]]

          means, stds = gp.predict(x_test, return_std: true)

          expect(means.size).to eq(1)
          expect(stds.size).to eq(1)
          expect(stds[0]).to be > 0
        end

        it 'has low uncertainty at training points' do
          x_test = [[2.0]]

          means, stds = gp.predict(x_test, return_std: true)

          expect(stds[0]).to be < 0.1
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
else
  RSpec.describe 'DSPy::Optimizers::GaussianProcess', :miprov2 do
    it 'skips when MIPROv2 dependencies are unavailable' do
      skip 'MIPROv2 optional dependencies are not installed'
    end
  end
end
