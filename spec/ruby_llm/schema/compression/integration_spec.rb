# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Schema Compression Integration" do
  let(:schema_class) do
    Class.new(RubyLLM::Schema) do
      string :first_name, description: "User's first name"
      string :last_name, description: "User's last name"
      integer :age

      object :address, description: "Mailing address" do
        string :street
        string :city
        string :zip_code
      end

      array :hobbies, of: :string, description: "List of hobbies"
    end
  end

  describe "#to_json_schema with compress: true" do
    let(:schema) { schema_class.new("UserProfile") }
    let(:result) { schema.to_json_schema(compress: true) }

    it "returns compressed schema with field_map" do
      expect(result).to have_key(:name)
      expect(result).to have_key(:schema)
      expect(result).to have_key(:field_map)
    end

    it "compresses top-level property names using first letters" do
      properties = result[:schema][:properties]
      # first_name => f, last_name => l, age => a, address => ad (conflict with age), hobbies => h
      expect(properties.keys).to contain_exactly("f", "l", "a", "ad", "h")
    end

    it "includes original names in descriptions" do
      properties = result[:schema][:properties]
      expect(properties["f"][:description]).to eq("first_name: User's first name")
      expect(properties["a"][:description]).to eq("age")
    end

    it "compresses nested object properties" do
      address = result[:schema][:properties]["ad"]
      # Nested properties: street => s, city => c, zip_code => z
      expect(address[:properties].keys).to contain_exactly("s", "c", "z")
      expect(address[:description]).to eq("address: Mailing address")
    end

    it "compresses required array" do
      expect(result[:schema][:required]).to contain_exactly("f", "l", "a", "ad", "h")
    end

    it "provides usable field_map for expansion" do
      # Simulate LLM response with compressed field names
      llm_response = {
        "f" => "John",
        "l" => "Doe",
        "a" => 30,
        "ad" => {
          "s" => "123 Main St",
          "c" => "Springfield",
          "z" => "12345"
        },
        "h" => ["reading", "coding"]
      }

      expanded = RubyLLM::Schema::Expander.expand(llm_response, result[:field_map])

      expect(expanded).to eq({
        first_name: "John",
        last_name: "Doe",
        age: 30,
        address: {
          street: "123 Main St",
          city: "Springfield",
          zip_code: "12345"
        },
        hobbies: ["reading", "coding"]
      })
    end
  end

  describe "#to_json with compress: true" do
    let(:schema) { schema_class.new("UserProfile") }

    it "returns JSON string with compressed schema" do
      result = schema.to_json(compress: true)
      parsed = JSON.parse(result)

      expect(parsed["schema"]["properties"].keys).to contain_exactly("f", "l", "a", "ad", "h")
      expect(parsed).to have_key("field_map")
    end
  end

  describe "round-trip compression and expansion" do
    context "with complex nested schema" do
      let(:complex_schema_class) do
        Class.new(RubyLLM::Schema) do
          string :title, description: "Document title"

          object :metadata do
            string :author
            string :created_at
            array :tags, of: :string
          end

          array :sections do
            object do
              string :heading
              string :content
              array :subsections do
                object do
                  string :subheading
                  string :text
                end
              end
            end
          end
        end
      end

      let(:schema) { complex_schema_class.new("Document") }

      it "correctly round-trips complex nested data" do
        compressed = schema.to_json_schema(compress: true)

        # Simulate a response using compressed field names
        field_map = compressed[:field_map]

        # Build response based on compressed names
        llm_response = build_compressed_response(compressed[:schema])

        expanded = RubyLLM::Schema::Expander.expand(llm_response, field_map)

        expect(expanded[:title]).to be_a(String)
        expect(expanded[:metadata]).to be_a(Hash)
        expect(expanded[:sections]).to be_a(Array)
      end

      def build_compressed_response(schema)
        # Helper to build a sample response matching the compressed schema structure
        result = {}
        schema[:properties].each do |key, prop|
          result[key] = case prop[:type]
          when "string"
            "sample"
          when "integer"
            42
          when "array"
            if prop[:items][:type] == "object"
              [build_compressed_response(prop[:items])]
            else
              ["item"]
            end
          when "object"
            build_compressed_response(prop)
          end
        end
        result
      end
    end

    context "with $defs and references" do
      let(:ref_schema_class) do
        Class.new(RubyLLM::Schema) do
          define :person do
            string :name, description: "Person's name"
            integer :age, description: "Person's age"
          end

          string :company_name, description: "Company name"
          object :ceo, of: :person
          array :employees, of: :person
        end
      end

      let(:schema) { ref_schema_class.new("Company") }

      it "compresses $defs and expands references correctly" do
        compressed = schema.to_json_schema(compress: true)

        # Verify $defs are compressed: name => n, age => a
        expect(compressed[:schema]["$defs"][:person][:properties].keys).to contain_exactly("n", "a")

        # Simulate response with compressed field names:
        # company_name => c, ceo => ce (conflict), employees => e
        # Inside $defs person: name => n, age => a
        llm_response = {
          "c" => "Acme Corp",
          "ce" => {"n" => "Jane CEO", "a" => 50},
          "e" => [
            {"n" => "John", "a" => 30},
            {"n" => "Jane", "a" => 25}
          ]
        }

        expanded = RubyLLM::Schema::Expander.expand(llm_response, compressed[:field_map])

        expect(expanded[:company_name]).to eq("Acme Corp")
        expect(expanded[:ceo]).to eq({name: "Jane CEO", age: 50})
        expect(expanded[:employees]).to eq([
          {name: "John", age: 30},
          {name: "Jane", age: 25}
        ])
      end
    end
  end

  describe "backward compatibility" do
    let(:schema) { schema_class.new("UserProfile") }

    it "returns uncompressed schema by default" do
      result = schema.to_json_schema

      properties = result[:schema][:properties]
      expect(properties.keys).to eq(%i[first_name last_name age address hobbies])
      expect(result).not_to have_key(:field_map)
    end

    it "returns uncompressed schema when compress: false" do
      result = schema.to_json_schema(compress: false)

      properties = result[:schema][:properties]
      expect(properties.keys).to eq(%i[first_name last_name age address hobbies])
    end
  end
end
