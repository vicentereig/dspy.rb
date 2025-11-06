# frozen_string_literal: true

require_relative '../constants'
require_relative 'normalize'
require_relative 'primitives'
require_relative 'writer'

module Sorbet
  module Toon
    module Encode
      module Encoders
        module_function

        ResolvedOptions = Struct.new(:indent, :delimiter, :length_marker, keyword_init: true)

        def encode_value(value, options)
          options = resolve_options(options)

          if Normalize.json_primitive?(value)
            return Primitives.encode_primitive(value, options.delimiter)
          end

          writer = Writer.new(options.indent)

          if Normalize.json_array?(value)
            encode_array(nil, value, writer, 0, options)
          elsif Normalize.json_object?(value)
            encode_object(value, writer, 0, options)
          end

          writer.to_s
        end

        def encode_object(object, writer, depth, options)
          object.each do |key, val|
            encode_key_value_pair(key, val, writer, depth, options)
          end
        end

        def encode_key_value_pair(key, value, writer, depth, options)
          encoded_key = Primitives.encode_key(key)

          if Normalize.json_primitive?(value)
            writer.push(depth, "#{encoded_key}: #{Primitives.encode_primitive(value, options.delimiter)}")
          elsif Normalize.json_array?(value)
            encode_array(key, value, writer, depth, options)
          elsif Normalize.json_object?(value)
            nested_keys = value.keys
            if nested_keys.empty?
              writer.push(depth, "#{encoded_key}:")
            else
              writer.push(depth, "#{encoded_key}:")
              encode_object(value, writer, depth + 1, options)
            end
          end
        end

        def encode_array(key, array, writer, depth, options)
          if array.empty?
            header = Primitives.format_header(0, key: key, delimiter: options.delimiter, length_marker: options.length_marker)
            writer.push(depth, header)
            return
          end

          if Normalize.array_of_primitives?(array)
            formatted = encode_inline_array_line(array, options.delimiter, key, options.length_marker)
            writer.push(depth, formatted)
            return
          end

          if Normalize.array_of_arrays?(array)
            all_primitive = array.all? { |arr| Normalize.array_of_primitives?(arr) }
            if all_primitive
              encode_array_of_arrays_as_list_items(key, array, writer, depth, options)
              return
            end
          end

          if Normalize.array_of_objects?(array)
            header = extract_tabular_header(array)
            if header
              encode_array_of_objects_as_tabular(key, array, header, writer, depth, options)
            else
              encode_mixed_array_as_list_items(key, array, writer, depth, options)
            end
            return
          end

          encode_mixed_array_as_list_items(key, array, writer, depth, options)
        end

        def encode_array_of_arrays_as_list_items(prefix, values, writer, depth, options)
          header = Primitives.format_header(values.length, key: prefix, delimiter: options.delimiter, length_marker: options.length_marker)
          writer.push(depth, header)

          values.each do |arr|
            next unless Normalize.array_of_primitives?(arr)

            inline = encode_inline_array_line(arr, options.delimiter, nil, options.length_marker)
            writer.push_list_item(depth + 1, inline)
          end
        end

        def encode_inline_array_line(values, delimiter, prefix = nil, length_marker = false)
          header = Primitives.format_header(values.length, key: prefix, delimiter: delimiter, length_marker: length_marker)
          return header if values.empty?

          joined = Primitives.encode_and_join_primitives(values, delimiter)
          "#{header} #{joined}"
        end

        def encode_array_of_objects_as_tabular(prefix, rows, header_keys, writer, depth, options)
          formatted_header = Primitives.format_header(
            rows.length,
            key: prefix,
            fields: header_keys,
            delimiter: options.delimiter,
            length_marker: options.length_marker
          )
          writer.push(depth, formatted_header)
          write_tabular_rows(rows, header_keys, writer, depth + 1, options)
        end

        def extract_tabular_header(rows)
          return nil if rows.empty?

          first_row = rows.first
          header = first_row.keys
          return nil if header.empty?
          return header if is_tabular_array(rows, header)

          nil
        end

        def is_tabular_array(rows, header)
          rows.all? do |row|
            keys = row.keys
            next false unless keys.length == header.length

            header.all? do |key|
              row.key?(key) && Normalize.json_primitive?(row[key])
            end
          end
        end

        def write_tabular_rows(rows, header, writer, depth, options)
          rows.each do |row|
            values = header.map { |key| row[key] }
            joined = Primitives.encode_and_join_primitives(values, options.delimiter)
            writer.push(depth, joined)
          end
        end

        def encode_mixed_array_as_list_items(prefix, items, writer, depth, options)
          header = Primitives.format_header(items.length, key: prefix, delimiter: options.delimiter, length_marker: options.length_marker)
          writer.push(depth, header)

          items.each do |item|
            encode_list_item_value(item, writer, depth + 1, options)
          end
        end

        def encode_object_as_list_item(object, writer, depth, options)
          keys = object.keys
          if keys.empty?
            writer.push(depth, Constants::LIST_ITEM_MARKER)
            return
          end

          first_key = keys.first
          first_value = object[first_key]
          encoded_first_key = Primitives.encode_key(first_key)

          if Normalize.json_primitive?(first_value)
            writer.push_list_item(depth, "#{encoded_first_key}: #{Primitives.encode_primitive(first_value, options.delimiter)}")
          elsif Normalize.json_array?(first_value)
            handle_first_array_item(encoded_first_key, first_key, first_value, writer, depth, options)
          elsif Normalize.json_object?(first_value)
            nested_keys = first_value.keys
            if nested_keys.empty?
              writer.push_list_item(depth, "#{encoded_first_key}:")
            else
              writer.push_list_item(depth, "#{encoded_first_key}:")
              encode_object(first_value, writer, depth + 2, options)
            end
          end

          keys.drop(1).each do |key|
            encode_key_value_pair(key, object[key], writer, depth + 1, options)
          end
        end

        def encode_list_item_value(value, writer, depth, options)
          if Normalize.json_primitive?(value)
            writer.push_list_item(depth, Primitives.encode_primitive(value, options.delimiter))
          elsif Normalize.json_array?(value) && Normalize.array_of_primitives?(value)
            inline = encode_inline_array_line(value, options.delimiter, nil, options.length_marker)
            writer.push_list_item(depth, inline)
          elsif Normalize.json_object?(value)
            encode_object_as_list_item(value, writer, depth, options)
          end
        end

        def handle_first_array_item(encoded_key, raw_key, array, writer, depth, options)
          if Normalize.array_of_primitives?(array)
            formatted = encode_inline_array_line(array, options.delimiter, raw_key, options.length_marker)
            writer.push_list_item(depth, formatted)
          elsif Normalize.array_of_objects?(array)
            header = extract_tabular_header(array)
            if header
              formatted_header = Primitives.format_header(
                array.length,
                key: raw_key,
                fields: header,
                delimiter: options.delimiter,
                length_marker: options.length_marker
              )
              writer.push_list_item(depth, formatted_header)
              write_tabular_rows(array, header, writer, depth + 1, options)
            else
              writer.push_list_item(depth, "#{encoded_key}[#{array.length}]:")
              array.each do |item|
                encode_object_as_list_item(item, writer, depth + 1, options)
              end
            end
          else
            writer.push_list_item(depth, "#{encoded_key}[#{array.length}]:")
            array.each do |item|
              encode_list_item_value(item, writer, depth + 1, options)
            end
          end
        end
        private_class_method :handle_first_array_item

        def resolve_options(opts)
          ResolvedOptions.new(
            indent: opts[:indent] || 2,
            delimiter: opts[:delimiter] || Constants::DEFAULT_DELIMITER,
            length_marker: opts[:length_marker] || false
          )
        end
        private_class_method :resolve_options
      end
    end
  end
end
