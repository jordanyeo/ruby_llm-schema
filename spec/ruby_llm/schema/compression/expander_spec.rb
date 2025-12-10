# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Schema::Expander do
  describe ".expand" do
    context "with simple flat response" do
      let(:field_map) do
        {
          "f" => :first_name,
          "l" => :last_name,
          "a" => :age
        }
      end

      it "expands short field names to original names" do
        response = {"f" => "John", "l" => "Doe", "a" => 30}

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          first_name: "John",
          last_name: "Doe",
          age: 30
        })
      end

      it "handles string keys in response" do
        response = {"f" => "John", "l" => "Doe"}

        result = described_class.expand(response, field_map)

        expect(result[:first_name]).to eq("John")
        expect(result[:last_name]).to eq("Doe")
      end

      it "preserves unmapped keys" do
        response = {"f" => "John", "unknown" => "value"}

        result = described_class.expand(response, field_map)

        expect(result[:first_name]).to eq("John")
        expect(result["unknown"]).to eq("value")
      end
    end

    context "with nested object response" do
      let(:field_map) do
        {
          "n" => :name,
          "a" => {
            :_original => :address,
            "s" => :street,
            "c" => :city,
            "z" => :zip_code
          }
        }
      end

      it "expands nested objects recursively" do
        response = {
          "n" => "John",
          "a" => {
            "s" => "123 Main St",
            "c" => "Springfield",
            "z" => "12345"
          }
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          name: "John",
          address: {
            street: "123 Main St",
            city: "Springfield",
            zip_code: "12345"
          }
        })
      end

      it "handles partial nested responses" do
        response = {
          "n" => "John",
          "a" => {"s" => "123 Main St"}
        }

        result = described_class.expand(response, field_map)

        expect(result[:name]).to eq("John")
        expect(result[:address][:street]).to eq("123 Main St")
      end
    end

    context "with array of objects response" do
      let(:field_map) do
        {
          "u" => {
            _original: :users,
            _items: {
              "n" => :name,
              "a" => :age
            }
          }
        }
      end

      it "expands each array item" do
        response = {
          "u" => [
            {"n" => "John", "a" => 30},
            {"n" => "Jane", "a" => 25}
          ]
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          users: [
            {name: "John", age: 30},
            {name: "Jane", age: 25}
          ]
        })
      end

      it "handles empty arrays" do
        response = {"u" => []}

        result = described_class.expand(response, field_map)

        expect(result).to eq({users: []})
      end
    end

    context "with array of primitives response" do
      let(:field_map) do
        {
          "t" => :tags
        }
      end

      it "preserves primitive arrays unchanged" do
        response = {"t" => ["ruby", "rails", "api"]}

        result = described_class.expand(response, field_map)

        expect(result).to eq({tags: ["ruby", "rails", "api"]})
      end
    end

    context "with anyOf variant response" do
      let(:field_map) do
        {
          "c" => {
            _original: :contact,
            _variants: [
              {"e" => :email},
              {"p" => :phone}
            ]
          }
        }
      end

      it "expands the matching variant by detecting keys" do
        email_response = {"c" => {"e" => "john@example.com"}}

        result = described_class.expand(email_response, field_map)

        expect(result).to eq({contact: {email: "john@example.com"}})
      end

      it "expands different variant" do
        phone_response = {"c" => {"p" => "555-1234"}}

        result = described_class.expand(phone_response, field_map)

        expect(result).to eq({contact: {phone: "555-1234"}})
      end
    end

    context "with $defs reference response" do
      let(:field_map) do
        {
          "f" => {
            _original: :founder,
            _ref: :person
          },
          "e" => {
            _original: :employees,
            _ref: :person
          },
          :_defs => {
            person: {"n" => :name, "a" => :age}
          }
        }
      end

      it "expands using $defs mapping for object references" do
        response = {
          "f" => {"n" => "Jane", "a" => 45}
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          founder: {name: "Jane", age: 45}
        })
      end

      it "expands using $defs mapping for array references" do
        response = {
          "e" => [
            {"n" => "John", "a" => 30},
            {"n" => "Jane", "a" => 25}
          ]
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          employees: [
            {name: "John", age: 30},
            {name: "Jane", age: 25}
          ]
        })
      end
    end

    context "with deeply nested structures" do
      let(:field_map) do
        {
          "c" => {
            :_original => :company,
            "n" => :name,
            "h" => {
              :_original => :headquarters,
              "a" => {
                :_original => :address,
                "s" => :street,
                "ci" => :city
              }
            }
          }
        }
      end

      it "expands all nesting levels" do
        response = {
          "c" => {
            "n" => "Acme Corp",
            "h" => {
              "a" => {
                "s" => "123 Business Ave",
                "ci" => "Metropolis"
              }
            }
          }
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          company: {
            name: "Acme Corp",
            headquarters: {
              address: {
                street: "123 Business Ave",
                city: "Metropolis"
              }
            }
          }
        })
      end
    end

    context "with nil values" do
      let(:field_map) do
        {
          "n" => :name,
          "e" => :email
        }
      end

      it "preserves nil values" do
        response = {"n" => "John", "e" => nil}

        result = described_class.expand(response, field_map)

        expect(result).to eq({name: "John", email: nil})
      end
    end

    context "with symbol keys option" do
      let(:field_map) do
        {
          "n" => :name,
          "a" => :age
        }
      end

      it "returns string keys when symbolize: false" do
        response = {"n" => "John", "a" => 30}

        result = described_class.expand(response, field_map, symbolize: false)

        expect(result).to eq({
          "name" => "John",
          "age" => 30
        })
      end
    end

    context "with anyOf containing array variant" do
      let(:field_map) do
        {
          "c" => {
            _original: :custom_fields,
            _variants: [
              {_items: {"f" => :field_name, "fi" => :field_value}},
              {}  # null variant
            ]
          }
        }
      end

      it "expands array values using the array variant's _items mapping" do
        response = {
          "c" => [
            {"f" => "Color", "fi" => "Blue"},
            {"f" => "Size", "fi" => "Large"}
          ]
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          custom_fields: [
            {field_name: "Color", field_value: "Blue"},
            {field_name: "Size", field_value: "Large"}
          ]
        })
      end

      it "handles null values" do
        response = {"c" => nil}

        result = described_class.expand(response, field_map)

        expect(result).to eq({custom_fields: nil})
      end
    end

    context "with deeply nested anyOf array structure" do
      let(:field_map) do
        {
          "s" => {
            _original: :samples,
            _items: {
              "sa" => :sample_name,
              "sv" => {
                _original: :sample_values,
                _variants: [
                  {_items: {"c" => :chemical_name, "v" => :value, "u" => :unit}},
                  {}  # null variant
                ]
              }
            }
          }
        }
      end

      it "expands deeply nested arrays within anyOf within arrays" do
        response = {
          "s" => [
            {
              "sa" => "Sample-001",
              "sv" => [
                {"c" => "Benzene", "v" => "< 5", "u" => "ug/L"},
                {"c" => "Toluene", "v" => "12.5", "u" => "ug/L"}
              ]
            },
            {
              "sa" => "Sample-002",
              "sv" => [
                {"c" => "Lead", "v" => "0.8", "u" => "mg/kg"}
              ]
            }
          ]
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          samples: [
            {
              sample_name: "Sample-001",
              sample_values: [
                {chemical_name: "Benzene", value: "< 5", unit: "ug/L"},
                {chemical_name: "Toluene", value: "12.5", unit: "ug/L"}
              ]
            },
            {
              sample_name: "Sample-002",
              sample_values: [
                {chemical_name: "Lead", value: "0.8", unit: "mg/kg"}
              ]
            }
          ]
        })
      end

      it "handles null values in nested anyOf" do
        response = {
          "s" => [
            {
              "sa" => "Sample-001",
              "sv" => nil
            }
          ]
        }

        result = described_class.expand(response, field_map)

        expect(result).to eq({
          samples: [
            {
              sample_name: "Sample-001",
              sample_values: nil
            }
          ]
        })
      end
    end
  end
end
