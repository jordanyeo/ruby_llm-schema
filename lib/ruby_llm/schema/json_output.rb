# frozen_string_literal: true

module RubyLLM
  class Schema
    module JsonOutput
      # Generates a JSON Schema representation
      #
      # @param compress [Boolean] Whether to compress field names (default: false)
      # @return [Hash] The JSON Schema hash, optionally with :field_map when compressed
      def to_json_schema(compress: false)
        validate!  # Validate schema before generating JSON

        if compress
          build_compressed_schema
        else
          build_standard_schema
        end
      end

      # Generates a JSON string representation
      #
      # @param compress [Boolean] Whether to compress field names (default: false)
      # @return [String] The JSON string
      def to_json(compress: false)
        validate!  # Validate schema before generating JSON string
        JSON.pretty_generate(to_json_schema(compress: compress))
      end

      private

      def build_standard_schema
        schema_hash = {
          type: "object",
          properties: self.class.properties,
          required: self.class.required_properties,
          additionalProperties: self.class.additional_properties,
          strict: self.class.strict
        }

        # Only include $defs if there are definitions
        schema_hash["$defs"] = self.class.definitions unless self.class.definitions.empty?

        {
          name: @name,
          description: @description || self.class.description,
          schema: schema_hash
        }
      end

      def build_compressed_schema
        compressed = Compressor.compress(
          self.class.properties,
          required: self.class.required_properties,
          definitions: self.class.definitions
        )

        schema_hash = {
          type: "object",
          properties: compressed[:properties],
          required: compressed[:required],
          additionalProperties: self.class.additional_properties,
          strict: self.class.strict
        }

        # Include compressed $defs if present
        schema_hash["$defs"] = compressed[:definitions] if compressed[:definitions]

        {
          name: @name,
          description: @description || self.class.description,
          schema: schema_hash,
          field_map: compressed[:field_map]
        }
      end
    end
  end
end
