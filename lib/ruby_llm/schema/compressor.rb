# frozen_string_literal: true

module RubyLLM
  class Schema
    # Compresses schema field names to short codes for token efficiency
    # when sending structured output schemas to LLMs.
    #
    # Field names are shortened to their first letter when possible,
    # with automatic conflict resolution using two letters when needed.
    #
    # @example
    #   # samples => s, title => t, summary => su (conflict with samples)
    #   result = Compressor.compress(schema.properties, required: schema.required_properties)
    #   # => { properties: {...}, required: [...], field_map: {...} }
    #
    class Compressor
      class << self
        # Generates a short name from a field name, avoiding conflicts
        #
        # @param name [String, Symbol] The original field name
        # @param used_names [Set] Set of already used short names
        # @return [String] The short name (1-2 characters)
        def short_name_for(name, used_names)
          name_str = name.to_s.downcase

          # Try first letter
          candidate = name_str[0]
          return candidate if candidate && !used_names.include?(candidate)

          # Try first two letters
          candidate = name_str[0, 2]
          return candidate if candidate && candidate.length == 2 && !used_names.include?(candidate)

          # Try first letter + each subsequent letter
          name_str[1..].each_char do |char|
            candidate = "#{name_str[0]}#{char}"
            return candidate unless used_names.include?(candidate)
          end

          # Fallback: first letter + incrementing suffix
          suffix = 1
          loop do
            candidate = "#{name_str[0]}#{suffix}"
            return candidate unless used_names.include?(candidate)
            suffix += 1
          end
        end

        # Compresses a schema's properties to use short field names
        #
        # @param properties [Hash] The properties hash from a schema
        # @param required [Array] Optional array of required property names
        # @param definitions [Hash] Optional $defs hash
        # @return [Hash] Compressed properties, required array, definitions, and field_map
        def compress(properties, required: [], definitions: {})
          context = CompressionContext.new

          # Compress $defs first (they get their own independent naming)
          defs_result = {}
          defs_field_map = {}

          unless definitions.empty?
            definitions.each do |def_name, def_schema|
              def_context = CompressionContext.new
              compressed_def = def_context.compress_schema(def_schema)
              defs_result[def_name] = compressed_def[:schema]
              defs_field_map[def_name] = compressed_def[:field_map]
            end
          end

          # Compress main properties
          result = context.compress_properties(properties, required, defs_field_map)

          # Add definitions to result if present
          unless definitions.empty?
            result[:definitions] = defs_result
            result[:field_map][:_defs] = defs_field_map
          end

          result
        end
      end

      # Internal context for tracking state during compression
      class CompressionContext
        def initialize
          @used_names = Set.new
        end

        def next_short_name(original_name)
          short = Compressor.short_name_for(original_name, @used_names)
          @used_names.add(short)
          short
        end

        # Compresses a properties hash
        #
        # @param properties [Hash] The properties to compress
        # @param required [Array] Array of required property names
        # @param defs_field_map [Hash] Field map for $defs (for reference resolution)
        # @return [Hash] { properties: {...}, required: [...], field_map: {...} }
        def compress_properties(properties, required = [], defs_field_map = {})
          compressed_props = {}
          compressed_required = []
          field_map = {}

          properties.each do |name, schema|
            short = next_short_name(name)
            name_sym = name.to_sym

            compressed_required << short if required.include?(name_sym)

            case schema_type(schema)
            when :object
              result = compress_object_schema(schema, name, defs_field_map)
              compressed_props[short] = result[:schema]
              field_map[short] = if result[:field_map].empty?
                name_sym
              else
                result[:field_map].merge(_original: name_sym)
              end
            when :array
              result = compress_array_schema(schema, name, defs_field_map)
              compressed_props[short] = result[:schema]
              field_map[short] = if result[:field_map]
                result[:field_map].merge(_original: name_sym)
              else
                name_sym
              end
            when :any_of
              result = compress_any_of_schema(schema, name, defs_field_map)
              compressed_props[short] = result[:schema]
              field_map[short] = result[:field_map].merge(_original: name_sym)
            when :one_of
              result = compress_one_of_schema(schema, name, defs_field_map)
              compressed_props[short] = result[:schema]
              field_map[short] = result[:field_map].merge(_original: name_sym)
            when :ref
              compressed_props[short] = add_description(schema.dup, name)
              # Extract the ref name for the field_map
              ref_name = schema["$ref"]&.split("/")&.last&.to_sym
              field_map[short] = {_original: name_sym, _ref: ref_name}
            else
              # Primitive type
              compressed_props[short] = add_description(schema.dup, name)
              field_map[short] = name_sym
            end
          end

          {
            properties: compressed_props,
            required: compressed_required,
            field_map: field_map
          }
        end

        # Compresses a complete schema (used for $defs)
        def compress_schema(schema)
          if schema[:type] == "object" && schema[:properties]
            result = compress_properties(schema[:properties], schema[:required] || [])
            compressed = schema.dup
            compressed[:properties] = result[:properties]
            compressed[:required] = result[:required] unless result[:required].empty?
            {schema: compressed, field_map: result[:field_map]}
          else
            {schema: schema, field_map: {}}
          end
        end

        private

        def schema_type(schema)
          return :ref if schema["$ref"]
          return :any_of if schema[:anyOf]
          return :one_of if schema[:oneOf]
          return :object if schema[:type] == "object"
          return :array if schema[:type] == "array"
          :primitive
        end

        def add_description(schema, original_name)
          original_desc = schema[:description]
          schema[:description] = if original_desc
            "#{original_name}: #{original_desc}"
          else
            original_name.to_s
          end
          schema
        end

        def compress_object_schema(schema, name, defs_field_map)
          compressed = schema.dup

          if schema[:properties]
            result = compress_properties(schema[:properties], schema[:required] || [], defs_field_map)
            compressed[:properties] = result[:properties]
            compressed[:required] = result[:required] unless result[:required].empty?
            compressed = add_description(compressed, name)
            {schema: compressed, field_map: result[:field_map]}
          else
            # Object without properties (e.g., reference)
            compressed = add_description(compressed, name)
            {schema: compressed, field_map: {}}
          end
        end

        def compress_array_schema(schema, name, defs_field_map)
          compressed = schema.dup
          compressed = add_description(compressed, name)

          items = schema[:items]
          return {schema: compressed, field_map: nil} unless items

          result = compress_array_items(items, defs_field_map)
          compressed[:items] = result[:schema] if result[:schema]
          {schema: compressed, field_map: result[:field_map]}
        end

        # Compresses array items - handles object, anyOf, oneOf, and ref item types
        def compress_array_items(items, defs_field_map)
          case schema_type(items)
          when :object
            if items[:properties]
              result = compress_properties(items[:properties], items[:required] || [], defs_field_map)
              compressed_items = items.dup
              compressed_items[:properties] = result[:properties]
              compressed_items[:required] = result[:required] unless result[:required].empty?
              {schema: compressed_items, field_map: {_items: result[:field_map]}}
            else
              {schema: items, field_map: nil}
            end
          when :any_of
            # Handle anyOf inside array items
            result = compress_any_of_items(items, defs_field_map)
            {schema: result[:schema], field_map: {_items: result[:field_map]}}
          when :one_of
            # Handle oneOf inside array items
            result = compress_one_of_items(items, defs_field_map)
            {schema: result[:schema], field_map: {_items: result[:field_map]}}
          when :ref
            ref_name = items["$ref"]&.split("/")&.last&.to_sym
            {schema: items, field_map: {_ref: ref_name}}
          else
            {schema: items, field_map: nil}
          end
        end

        # Compress anyOf schema that appears as array items (no name/description handling)
        def compress_any_of_items(schema, defs_field_map)
          compressed = schema.dup
          variants_field_map = []

          compressed_any_of = schema[:anyOf].map do |variant|
            compress_variant(variant, variants_field_map, defs_field_map)
          end

          compressed[:anyOf] = compressed_any_of
          {schema: compressed, field_map: {_variants: variants_field_map}}
        end

        # Compress oneOf schema that appears as array items (no name/description handling)
        def compress_one_of_items(schema, defs_field_map)
          compressed = schema.dup
          variants_field_map = []

          compressed_one_of = schema[:oneOf].map do |variant|
            compress_variant(variant, variants_field_map, defs_field_map)
          end

          compressed[:oneOf] = compressed_one_of
          {schema: compressed, field_map: {_variants: variants_field_map}}
        end

        # Compress a single variant (object, array, or primitive)
        def compress_variant(variant, variants_field_map, defs_field_map)
          if variant[:type] == "object" && variant[:properties]
            result = compress_properties(variant[:properties], variant[:required] || [], defs_field_map)
            variants_field_map << result[:field_map]
            compressed_variant = variant.dup
            compressed_variant[:properties] = result[:properties]
            compressed_variant[:required] = result[:required] unless result[:required].empty?
            compressed_variant
          elsif variant[:type] == "array" && variant[:items]
            result = compress_array_items(variant[:items], defs_field_map)
            variants_field_map << result[:field_map]
            compressed_variant = variant.dup
            compressed_variant[:items] = result[:schema] if result[:schema]
            compressed_variant
          else
            variants_field_map << {}
            variant
          end
        end

        def compress_any_of_schema(schema, name, defs_field_map)
          compressed = schema.dup
          compressed = add_description(compressed, name)

          variants_field_map = []
          compressed_any_of = schema[:anyOf].map do |variant|
            compress_variant(variant, variants_field_map, defs_field_map)
          end

          compressed[:anyOf] = compressed_any_of
          {schema: compressed, field_map: {_variants: variants_field_map}}
        end

        def compress_one_of_schema(schema, name, defs_field_map)
          compressed = schema.dup
          compressed = add_description(compressed, name)

          variants_field_map = []
          compressed_one_of = schema[:oneOf].map do |variant|
            compress_variant(variant, variants_field_map, defs_field_map)
          end

          compressed[:oneOf] = compressed_one_of
          {schema: compressed, field_map: {_variants: variants_field_map}}
        end
      end
    end
  end
end
