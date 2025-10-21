# typed: strict
# frozen_string_literal: true

require 'numo/narray'
require 'numo/tiny_linalg'
require 'sorbet-runtime'

module DSPy
  module Optimizers
    # Gaussian Process regression backed by Numo::TinyLinalg for Bayesian optimization.
    class GaussianProcess
      extend T::Sig

      sig { params(length_scale: Float, signal_variance: Float, noise_variance: Float).void }
      def initialize(length_scale: 1.0, signal_variance: 1.0, noise_variance: 1e-6)
        @length_scale = length_scale
        @signal_variance = signal_variance
        @noise_variance = noise_variance
        @fitted = T.let(false, T::Boolean)
      end

      sig { params(x_train: T::Array[T::Array[Float]], y_train: T::Array[Float]).void }
      def fit(x_train, y_train)
        x_matrix = to_matrix(x_train)
        y_vector = to_vector(y_train)

        kernel_matrix = rbf_kernel(x_matrix, x_matrix)
        kernel_matrix += Numo::DFloat.eye(kernel_matrix.shape[0]) * @noise_variance

        @cholesky_factor = Numo::TinyLinalg.cholesky(kernel_matrix, uplo: 'L')
        @alpha = Numo::TinyLinalg.cho_solve(@cholesky_factor, y_vector, uplo: 'L')

        @x_train = x_matrix
        @y_train = y_vector
        @fitted = true
      end

      sig do
        params(x_test: T::Array[T::Array[Float]], return_std: T::Boolean)
          .returns(T.any(Numo::DFloat, [Numo::DFloat, Numo::DFloat]))
      end
      def predict(x_test, return_std: false)
        raise 'Gaussian Process not fitted' unless @fitted

        test_matrix = to_matrix(x_test)
        k_star = rbf_kernel(T.must(@x_train), test_matrix)

        mean = k_star.transpose.dot(T.must(@alpha))
        return mean unless return_std

        v = Numo::TinyLinalg.cho_solve(T.must(@cholesky_factor), k_star, uplo: 'L')
        k_star_star = rbf_kernel(test_matrix, test_matrix)
        covariance = k_star_star - k_star.transpose.dot(v)

        variance = covariance.diagonal.dup
        variance[variance < 1e-12] = 1e-12
        std = Numo::NMath.sqrt(variance)

        [mean, std]
      end

      private

      sig { params(x1: Numo::DFloat, x2: Numo::DFloat).returns(Numo::DFloat) }
      def rbf_kernel(x1, x2)
        scaled = 1.0 / (@length_scale**2)
        x1_sq = (x1**2).sum(axis: 1).reshape(x1.shape[0], 1)
        x2_sq = (x2**2).sum(axis: 1).reshape(1, x2.shape[0])
        sqdist = x1_sq - 2.0 * x1.dot(x2.transpose) + x2_sq
        @signal_variance * Numo::NMath.exp(-0.5 * sqdist * scaled)
      end

      sig { params(data: T::Array[T::Array[Float]]).returns(Numo::DFloat) }
      def to_matrix(data)
        matrix = Numo::DFloat[*data]
        matrix = matrix.reshape(matrix.size, 1) if matrix.ndim == 1
        matrix
      end

      sig { params(data: T::Array[Float]).returns(Numo::DFloat) }
      def to_vector(data)
        Numo::DFloat[*data]
      end
    end
  end
end
