# typed: strict
# frozen_string_literal: true

require 'numo/narray'
require 'sorbet-runtime'

module DSPy
  module Optimizers
    # Pure Ruby Gaussian Process implementation for Bayesian optimization
    # No external LAPACK/BLAS dependencies required
    class GaussianProcess
      extend T::Sig

      sig { params(length_scale: Float, signal_variance: Float, noise_variance: Float).void }
      def initialize(length_scale: 1.0, signal_variance: 1.0, noise_variance: 1e-6)
        @length_scale = length_scale
        @signal_variance = signal_variance
        @noise_variance = noise_variance
        @fitted = T.let(false, T::Boolean)
      end

      sig { params(x1: T::Array[T::Array[Float]], x2: T::Array[T::Array[Float]]).returns(Numo::DFloat) }
      def rbf_kernel(x1, x2)
        # Convert to Numo arrays
        x1_array = Numo::DFloat[*x1]
        x2_array = Numo::DFloat[*x2]
        
        # Compute squared Euclidean distances manually
        n1, n2 = x1_array.shape[0], x2_array.shape[0]
        sqdist = Numo::DFloat.zeros(n1, n2)
        
        (0...n1).each do |i|
          (0...n2).each do |j|
            diff = x1_array[i, true] - x2_array[j, true]
            sqdist[i, j] = (diff ** 2).sum
          end
        end
        
        # RBF kernel: σ² * exp(-0.5 * d² / ℓ²)
        @signal_variance * Numo::NMath.exp(-0.5 * sqdist / (@length_scale ** 2))
      end

      sig { params(x_train: T::Array[T::Array[Float]], y_train: T::Array[Float]).void }
      def fit(x_train, y_train)
        @x_train = x_train
        @y_train = Numo::DFloat[*y_train]
        
        # Compute kernel matrix
        k_matrix = rbf_kernel(x_train, x_train)
        
        # Add noise to diagonal for numerical stability
        n = k_matrix.shape[0]
        (0...n).each { |i| k_matrix[i, i] += @noise_variance }
        
        # Store inverted kernel matrix using simple LU decomposition
        @k_inv = matrix_inverse(k_matrix)
        @alpha = @k_inv.dot(@y_train)
        
        @fitted = true
      end

      sig { params(x_test: T::Array[T::Array[Float]], return_std: T::Boolean).returns(T.any(Numo::DFloat, [Numo::DFloat, Numo::DFloat])) }
      def predict(x_test, return_std: false)
        raise "Gaussian Process not fitted" unless @fitted
        
        # Kernel between training and test points
        k_star = rbf_kernel(T.must(@x_train), x_test)
        
        # Predictive mean
        mean = k_star.transpose.dot(@alpha)
        
        return mean unless return_std
        
        # Predictive variance (simplified for small matrices)
        k_star_star = rbf_kernel(x_test, x_test)
        var_matrix = k_star_star - k_star.transpose.dot(@k_inv).dot(k_star)
        var = var_matrix.diagonal
        
        # Ensure positive variance (element-wise maximum)
        var = var.map { |v| [v, 1e-12].max }
        std = Numo::NMath.sqrt(var)
        
        [mean, std]
      end

      private

      sig { returns(T.nilable(T::Array[T::Array[Float]])) }
      attr_reader :x_train

      sig { returns(T.nilable(Numo::DFloat)) }
      attr_reader :y_train, :k_inv, :alpha

      # Simple matrix inversion using Gauss-Jordan elimination
      # Only suitable for small matrices (< 100x100)
      sig { params(matrix: Numo::DFloat).returns(Numo::DFloat) }
      def matrix_inverse(matrix)
        n = matrix.shape[0]
        raise "Matrix must be square" unless matrix.shape[0] == matrix.shape[1]
        
        # Create augmented matrix [A|I]
        augmented = Numo::DFloat.zeros(n, 2*n)
        augmented[true, 0...n] = matrix.copy
        (0...n).each { |i| augmented[i, n+i] = 1.0 }
        
        # Gauss-Jordan elimination
        (0...n).each do |i|
          # Find pivot
          max_row = i
          (i+1...n).each do |k|
            if augmented[k, i].abs > augmented[max_row, i].abs
              max_row = k
            end
          end
          
          # Swap rows if needed
          if max_row != i
            temp = augmented[i, true].copy
            augmented[i, true] = augmented[max_row, true]
            augmented[max_row, true] = temp
          end
          
          # Make diagonal element 1
          pivot = augmented[i, i]
          raise "Matrix is singular" if pivot.abs < 1e-12
          augmented[i, true] /= pivot
          
          # Eliminate column
          (0...n).each do |j|
            next if i == j
            factor = augmented[j, i]
            augmented[j, true] -= factor * augmented[i, true]
          end
        end
        
        # Extract inverse matrix
        augmented[true, n...2*n]
      end
    end
  end
end