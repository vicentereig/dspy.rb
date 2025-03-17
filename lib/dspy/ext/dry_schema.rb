Dry::Schema.load_extensions(:json_schema)
# Monkey patch Macros::Core to add meta method
module Dry
  module Schema
    module Macros
      class Core
        def meta(metadata)
          schema_dsl.meta(name, metadata)
          self
        end
      end
    end
  end
end

# Monkey patch DSL to store metadata
module Dry
  module Schema
    class DSL
      def meta(name, metadata)
        @metas ||= {}
        @metas[name] = metadata
        self
      end

      def metas
        @metas ||= {}
      end

      # Ensure metas are included in new instances
      alias_method :original_new, :new
      def new(**options, &block)
        options[:metas] = metas
        original_new(**options, &block)
      end

      # Ensure processor has access to metas
      alias_method :original_call, :call
      def call
        processor = original_call
        processor.instance_variable_set(:@schema_metas, metas)
        processor
      end
    end
  end
end

# Monkey patch Processor to expose schema_metas
module Dry
  module Schema
    class Processor
      attr_reader :schema_metas

      # Add schema_metas accessor
      def schema_metas
        @schema_metas ||= {}
      end
    end
  end
end

# Directly monkey patch the JSON Schema generation
module Dry
  module Schema
    module JSONSchema
      module SchemaMethods
        # Override the original json_schema method
        def json_schema(loose: false)
          compiler = SchemaCompiler.new(root: true, loose: loose)
          compiler.call(to_ast)
          result = compiler.to_hash

          # Add descriptions to properties from schema_metas
          if respond_to?(:schema_metas) && !schema_metas.empty?
            schema_metas.each do |key, meta|
              if meta[:description] && result[:properties][key]
                result[:properties][key][:description] = meta[:description]
              end
            end
          end

          result
        end
      end
    end
  end
end

