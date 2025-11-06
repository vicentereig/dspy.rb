# frozen_string_literal: true

module Sorbet
  module Toon
    module StructExtensions
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def from_toon(payload, **options)
          Sorbet::Toon.decode(payload, struct_class: self, **options)
        end
      end

      def to_toon(**options)
        Sorbet::Toon.encode(self, **options)
      end
    end
  end
end
