# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Ext
    # Extends T::Struct to support field descriptions via the :description kwarg.
    #
    # This module is prepended to T::Struct to intercept const/prop definitions
    # and capture descriptions before they reach Sorbet (which doesn't support them).
    #
    # @example
    #   class ASTNode < T::Struct
    #     const :node_type, String, description: 'The type of AST node'
    #     const :text, String, default: "", description: 'Text content of the node'
    #     const :children, T::Array[ASTNode], default: []
    #   end
    #
    #   ASTNode.field_descriptions[:node_type]  # => "The type of AST node"
    #   ASTNode.field_descriptions[:text]       # => "Text content of the node"
    #   ASTNode.field_descriptions[:children]   # => nil (no description)
    #
    module StructDescriptions
      def self.prepended(base)
        base.singleton_class.prepend(ClassMethods)
      end

      module ClassMethods
        # Returns a hash of field names to their descriptions.
        # Only fields with explicit :description kwargs are included.
        #
        # @return [Hash{Symbol => String}]
        def field_descriptions
          @field_descriptions ||= {}
        end

        # Intercepts const definitions to capture :description before Sorbet sees it.
        def const(name, type, **kwargs)
          if kwargs.key?(:description)
            field_descriptions[name] = kwargs.delete(:description)
          end
          super(name, type, **kwargs)
        end

        # Intercepts prop definitions to capture :description before Sorbet sees it.
        def prop(name, type, **kwargs)
          if kwargs.key?(:description)
            field_descriptions[name] = kwargs.delete(:description)
          end
          super(name, type, **kwargs)
        end
      end
    end
  end
end

# Apply the extension to T::Struct globally
T::Struct.prepend(DSPy::Ext::StructDescriptions)
