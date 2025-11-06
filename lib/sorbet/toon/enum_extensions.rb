# frozen_string_literal: true

module Sorbet
  module Toon
    module EnumExtensions
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def from_toon(payload, **options)
          value = Sorbet::Toon.decode(payload, **options)
          return value if value.is_a?(self)

          if respond_to?(:deserialize)
            deserialize(value)
          else
            values.find { |member| member.serialize == value }
          end
        end
      end

      def to_toon(**options)
        Sorbet::Toon.encode(serialize, **options)
      end
    end
  end
end
