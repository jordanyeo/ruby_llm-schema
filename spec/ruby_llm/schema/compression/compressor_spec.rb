# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Schema::Compressor do
  describe ".short_name_for" do
    it "uses first letter when no conflicts" do
      used = Set.new
      expect(described_class.short_name_for(:name, used)).to eq("n")
      expect(described_class.short_name_for(:age, used)).to eq("a")
    end

    it "uses first two letters when first letter conflicts" do
      used = Set.new(["s"])
      expect(described_class.short_name_for(:summary, used)).to eq("su")
    end

    it "tries other letters from the name when first two conflict" do
      used = Set.new(["s", "su"])
      # samples: tries s (taken), su (taken), sa, sm, sp, sl, se, ss
      expect(described_class.short_name_for(:samples, used)).to eq("sa")
    end

    it "falls back to numeric suffix when all letters exhausted" do
      used = Set.new(["a", "ab"])
      # For a very short name like "ab", after trying a, ab, we go to a1
      expect(described_class.short_name_for(:ab, used)).to eq("a1")
    end
  end

  describe ".compress" do
    context "with simple flat schema" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          string :first_name, description: "User's first name"
          string :last_name
          integer :age, description: "User's age in years"
        end
      end

      it "replaces property names with short codes based on first letter" do
        result = described_class.compress(schema_class.properties)

        # first_name => f, last_name => l, age => a
        expect(result[:properties].keys).to contain_exactly("f", "l", "a")
      end

      it "prepends original field name to existing descriptions" do
        result = described_class.compress(schema_class.properties)

        expect(result[:properties]["f"][:description]).to eq("first_name: User's first name")
        expect(result[:properties]["a"][:description]).to eq("age: User's age in years")
      end

      it "uses original field name as description when none exists" do
        result = described_class.compress(schema_class.properties)

        expect(result[:properties]["l"][:description]).to eq("last_name")
      end

      it "returns a field_map for expansion" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]).to eq({
          "f" => :first_name,
          "l" => :last_name,
          "a" => :age
        })
      end

      it "returns compressed required properties" do
        result = described_class.compress(
          schema_class.properties,
          required: schema_class.required_properties
        )

        expect(result[:required]).to contain_exactly("f", "l", "a")
      end
    end

    context "with conflicting first letters" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          string :summary, description: "Brief summary"
          string :samples, description: "Sample data"
          string :source
        end
      end

      it "resolves conflicts using two letters" do
        result = described_class.compress(schema_class.properties)

        # summary => s, samples => sa (conflict), source => so (conflict)
        expect(result[:properties].keys).to contain_exactly("s", "sa", "so")
      end

      it "maintains correct field_map" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]["s"]).to eq(:summary)
        expect(result[:field_map]["sa"]).to eq(:samples)
        expect(result[:field_map]["so"]).to eq(:source)
      end
    end

    context "with nested object properties" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          string :name
          object :address, description: "Mailing address" do
            string :street, description: "Street address"
            string :city
            string :zip_code
          end
        end
      end

      it "compresses nested object properties independently" do
        result = described_class.compress(schema_class.properties)

        # Top level: name => n, address => a
        expect(result[:properties].keys).to contain_exactly("n", "a")

        # Nested object properties: street => s, city => c, zip_code => z
        address = result[:properties]["a"]
        expect(address[:properties].keys).to contain_exactly("s", "c", "z")
      end

      it "returns nested field_map" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]["n"]).to eq(:name)
        expect(result[:field_map]["a"]).to include(_original: :address)
        expect(result[:field_map]["a"]["s"]).to eq(:street)
        expect(result[:field_map]["a"]["c"]).to eq(:city)
        expect(result[:field_map]["a"]["z"]).to eq(:zip_code)
      end
    end

    context "with array of objects" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          array :users do
            object do
              string :name
              integer :age
            end
          end
        end
      end

      it "compresses array item properties" do
        result = described_class.compress(schema_class.properties)

        # users => u, then item properties: name => n, age => a
        items = result[:properties]["u"][:items]
        expect(items[:type]).to eq("object")
        expect(items[:properties].keys).to contain_exactly("n", "a")
      end

      it "includes array items in field_map" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]["u"][:_original]).to eq(:users)
        expect(result[:field_map]["u"][:_items]).to eq({
          "n" => :name,
          "a" => :age
        })
      end
    end

    context "with array of primitives" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          array :tags, of: :string, description: "List of tags"
        end
      end

      it "does not add nested mapping for primitive arrays" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]).to eq({
          "t" => :tags
        })
      end

      it "preserves array structure" do
        result = described_class.compress(schema_class.properties)

        expect(result[:properties]["t"]).to include(
          type: "array",
          items: {type: "string"}
        )
        expect(result[:properties]["t"][:description]).to eq("tags: List of tags")
      end
    end

    context "with anyOf/oneOf types" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          any_of :contact do
            object do
              string :email
            end
            object do
              string :phone
            end
          end
        end
      end

      it "compresses each variant in anyOf" do
        result = described_class.compress(schema_class.properties)

        # contact => c, email => e, phone => p
        any_of = result[:properties]["c"][:anyOf]
        expect(any_of[0][:properties].keys).to eq(["e"])
        expect(any_of[1][:properties].keys).to eq(["p"])
      end

      it "includes all variants in field_map" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]["c"][:_original]).to eq(:contact)
        expect(result[:field_map]["c"][:_variants]).to eq([
          {"e" => :email},
          {"p" => :phone}
        ])
      end
    end

    context "with $defs and references" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          define :person do
            string :name
            integer :age
          end

          object :founder, of: :person
          array :employees, of: :person
        end
      end

      it "compresses $defs schemas" do
        result = described_class.compress(
          schema_class.properties,
          definitions: schema_class.definitions
        )

        # In $defs: name => n, age => a
        person_def = result[:definitions][:person]
        expect(person_def[:properties].keys).to contain_exactly("n", "a")
      end

      it "includes $defs in field_map" do
        result = described_class.compress(
          schema_class.properties,
          definitions: schema_class.definitions
        )

        expect(result[:field_map][:_defs]).to eq({
          person: {"n" => :name, "a" => :age}
        })
      end

      it "does not compress $ref pointers" do
        result = described_class.compress(
          schema_class.properties,
          definitions: schema_class.definitions
        )

        # Main properties: founder => f, employees => e
        expect(result[:properties]["f"]).to include("$ref" => "#/$defs/person")
        expect(result[:properties]["e"][:items]).to include("$ref" => "#/$defs/person")
      end
    end

    context "with anyOf containing array variant" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          any_of :custom_fields, description: "Optional custom fields" do
            array do
              object do
                string :field_name, description: "Name of the custom field"
                string :field_value, description: "Value of the custom field"
              end
            end
            null
          end
        end
      end

      it "compresses array items inside anyOf" do
        result = described_class.compress(schema_class.properties)

        # custom_fields => c
        any_of = result[:properties]["c"][:anyOf]

        # First variant is an array with compressed item properties
        array_variant = any_of[0]
        expect(array_variant[:type]).to eq("array")
        expect(array_variant[:items][:properties].keys).to contain_exactly("f", "fi")
      end

      it "includes array items in variants field_map" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]["c"][:_original]).to eq(:custom_fields)
        expect(result[:field_map]["c"][:_variants]).to be_an(Array)

        # First variant should have _items mapping for the array
        array_variant_map = result[:field_map]["c"][:_variants][0]
        expect(array_variant_map[:_items]).to eq({
          "f" => :field_name,
          "fi" => :field_value
        })

        # Second variant (null) should be empty
        expect(result[:field_map]["c"][:_variants][1]).to eq({})
      end
    end

    context "with deeply nested anyOf array structure" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          array :samples, description: "List of samples" do
            object do
              string :sample_name
              any_of :sample_values, description: "Analytical results" do
                array do
                  object do
                    string :chemical_name, description: "Name of chemical"
                    string :value, description: "Measured value"
                    string :unit, description: "Unit of measurement"
                  end
                end
                null
              end
            end
          end
        end
      end

      it "compresses nested arrays within anyOf within arrays" do
        result = described_class.compress(schema_class.properties)

        # samples => s
        samples = result[:properties]["s"]
        expect(samples[:type]).to eq("array")

        # sample item properties: sample_name => sa, sample_values => sv (or similar)
        item_props = samples[:items][:properties]
        expect(item_props.keys.length).to eq(2)

        # Find the sample_values key (it will be some short name)
        sample_values_key = item_props.keys.find { |k| item_props[k][:anyOf] }
        sample_values = item_props[sample_values_key]

        # anyOf should have array variant with compressed properties
        array_variant = sample_values[:anyOf].find { |v| v[:type] == "array" }
        expect(array_variant[:items][:properties].keys).to contain_exactly("c", "v", "u")
      end

      it "builds deeply nested field_map for expansion" do
        result = described_class.compress(schema_class.properties)

        # samples field_map
        samples_map = result[:field_map]["s"]
        expect(samples_map[:_original]).to eq(:samples)

        # samples items field_map
        items_map = samples_map[:_items]
        expect(items_map).to be_a(Hash)

        # Find sample_values in items_map
        sample_values_map = items_map.values.find { |v| v.is_a?(Hash) && v[:_variants] }
        expect(sample_values_map).not_to be_nil
        expect(sample_values_map[:_original]).to eq(:sample_values)

        # First variant should have _items for the nested array
        array_variant_map = sample_values_map[:_variants][0]
        expect(array_variant_map[:_items]).to include(
          "c" => :chemical_name,
          "v" => :value,
          "u" => :unit
        )
      end
    end

    context "with deeply nested structures" do
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          object :company do
            string :name
            object :headquarters do
              object :address do
                string :street
                string :city
              end
            end
          end
        end
      end

      it "compresses all levels with shared context to avoid collisions" do
        result = described_class.compress(schema_class.properties)

        # company => c
        company = result[:properties]["c"]
        # company.name => n, company.headquarters => h
        expect(company[:properties].keys).to contain_exactly("n", "h")

        # headquarters.address => a
        hq = company[:properties]["h"]
        expect(hq[:properties].keys).to eq(["a"])

        # address.street => s, address.city => ci (c is taken by company)
        address = hq[:properties]["a"]
        expect(address[:properties].keys).to contain_exactly("s", "ci")
      end

      it "builds deeply nested field_map" do
        result = described_class.compress(schema_class.properties)

        expect(result[:field_map]["c"][:_original]).to eq(:company)
        expect(result[:field_map]["c"]["n"]).to eq(:name)
        expect(result[:field_map]["c"]["h"][:_original]).to eq(:headquarters)
        expect(result[:field_map]["c"]["h"]["a"][:_original]).to eq(:address)
        expect(result[:field_map]["c"]["h"]["a"]["s"]).to eq(:street)
        expect(result[:field_map]["c"]["h"]["a"]["ci"]).to eq(:city)
      end
    end
  end
end
