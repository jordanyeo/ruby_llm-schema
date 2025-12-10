# RubyLLM::Schema

[![Gem Version](https://badge.fury.io/rb/ruby_llm-schema.svg)](https://rubygems.org/gems/ruby_llm-schema)
[![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/danielfriis/ruby_llm-schema/blob/main/LICENSE.txt)
[![CI](https://github.com/danielfriis/ruby_llm-schema/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/danielfriis/ruby_llm-schema/actions/workflows/ci.yml)

A Ruby DSL for creating JSON schemas with a clean, Rails-inspired API. Perfect for defining structured data schemas for LLM function calling or structured outputs.

## Use Cases

Structured output is a powerful tool for LLMs to generate consistent and predictable responses.

Some ideal use cases:

- Extracting *metadata, topics, and summary* from articles or blog posts
- Organizing unstructured feedback or reviews with *sentiment and summary* 
- Defining structured *actions* from user messages or emails
- Extracting *entities and relationships* from documents

### Simple Example

```ruby
class PersonSchema < RubyLLM::Schema
  string :name, description: "Person's full name"
  number :age, description: "Age in years", minimum: 0, maximum: 120
  boolean :active, required: false
  
  object :address do
    string :street
    string :city
    string :country, required: false
  end
  
  array :tags, of: :string, description: "User tags"
  
  array :contacts do
    object do
      string :email, format: "email"
      string :phone, required: false
    end
  end
  
  any_of :status do
    string enum: ["active", "pending", "inactive"]
    null
  end
end

# Usage
schema = PersonSchema.new
puts schema.to_json
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_llm-schema'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ruby_llm-schema
```

## Usage

Three approaches for creating schemas:

### Class Inheritance

```ruby
class PersonSchema < RubyLLM::Schema
  string :name, description: "Person's full name"
  number :age
  boolean :active, required: false
  
  object :address do
    string :street
    string :city
  end
  
  array :tags, of: :string
end

schema = PersonSchema.new
puts schema.to_json
```

### Factory Method

```ruby
PersonSchema = RubyLLM::Schema.create do
  string :name, description: "Person's full name"
  number :age
  boolean :active, required: false
  
  object :address do
    string :street
    string :city
  end
  
  array :tags, of: :string
end

schema = PersonSchema.new
puts schema.to_json
```

### Global Helper

```ruby
require 'ruby_llm/schema'
include RubyLLM::Helpers

person_schema = schema "PersonData", description: "A person object" do
  string :name, description: "Person's full name"
  number :age
  boolean :active, required: false
  
  object :address do
    string :street
    string :city
  end
  
  array :tags, of: :string
end

puts person_schema.to_json
```

## Schema Property Types

A schema is a collection of properties, which can be of different types. Each type has its own set of properties you can set.

All property types can (along with the required `name` key) be set with a `description` and a `required` flag (default is `true`).

```ruby
string :name, description: "Person's full name"
number :age, description: "Person's age", required: false
boolean :is_active, description: "Whether the person is active"
null :placeholder, description: "A placeholder property"
```

⚠️ Please consult the LLM provider documentation for any limitations or restrictions. For example, as of now, OpenAI requires all properties to be required. In that case, you can use the `any_of` method to make a property optional.

```ruby
any_of :name, description: "Person's full name" do
  string
  null
end
```

### Strings

String types support the following properties:

- `enum`: an array of allowed values (e.g. `enum: ["on", "off"]`)
- `pattern`: a regex pattern (e.g. `pattern: "\\d+"`)
- `format`: a format string (e.g. `format: "email"`)
- `min_length`: the minimum length of the string (e.g. `min_length: 3`)
- `max_length`: the maximum length of the string (e.g. `max_length: 10`)

Please consult the LLM provider documentation for the available formats and patterns.

```ruby
string :name, description: "Person's full name"
string :email, format: "email"
string :phone, pattern: "\\d+"
string :status, enum: ["on", "off"]
string :code, min_length: 3, max_length: 10
```

### Numbers

Number types support the following properties:

- `multiple_of`: a multiple of the number (e.g. `multiple_of: 0.01`)
- `minimum`: the minimum value of the number (e.g. `minimum: 0`)
- `maximum`: the maximum value of the number (e.g. `maximum: 100`)

```ruby
number :price, minimum: 0, maximum: 100
number :amount, multiple_of: 0.01
```

### Booleans

```ruby
boolean :is_active
```

Boolean types doesn't support any additional properties.

### Null

```ruby
null :placeholder
```

Null types doesn't support any additional properties.

### Arrays

An array is a list of items. You can set the type of the items in the array with the `of` option or by passing a block with the `object` method.

An array can have a `min_items` and `max_items` option to set the minimum and maximum number of items in the array.

```ruby
array :tags, of: :string              # Array of strings
array :scores, of: :number            # Array of numbers
array :items, min_items: 1, max_items: 10  # Array with size constraints

array :items do                       # Array of objects
  object do
    string :name
    number :price
  end
end
```

### Objects

Objects types expect a block with the properties of the object.

```ruby
object :user do
  string :name
  number :age
end

object :settings, description: "User preferences" do
  boolean :notifications
  string :theme, enum: ["light", "dark"]
end
```

### Union Types (anyOf)

Union types are a way to specify that a property can be one of several types.

```ruby
any_of :value do
  string
  number  
  null
end

any_of :identifier do
  string description: "Username"
  number description: "User ID"
end
```

### Schema Definitions and References

You can define sub-schemas and reference them in other schemas, or reference the root schema to generate recursive schemas.

```ruby
class MySchema < RubyLLM::Schema
  define :location do
    string :latitude
    string :longitude
  end
  
  # Using a reference in an array
  array :coordinates, of: :location

  # Using a reference in an object via the `reference` option
  object :home_location, reference: :location

  # Using a reference in an object via block
  object :user do
    reference :location
  end

  # Using a reference to the root schema
  object :ui_schema do
    string :element, enum: ["input", "button"]
    string :label
    object :sub_schema, reference: :root
  end
end
```

### Nested Schemas

You can embed existing schema classes directly within objects or arrays for reusable schema composition.

```ruby
class PersonSchema < RubyLLM::Schema
  string :name
  integer :age
end

class CompanySchema < RubyLLM::Schema
  # Using 'of' parameter
  object :ceo, of: PersonSchema
  array :employees, of: PersonSchema
  
  # Using Schema.new in block
  object :founder do
    PersonSchema.new
  end
end

schema = CompanySchema.new
schema.to_json_schema
# =>
# {
#    "name":"CompanySchema",
#    "description":"nil",
#    "schema":{
#       "type":"object",
#       "properties":{
#          "ceo":{
#             "type":"object",
#             "properties":{
#                "name":{
#                   "type":"string"
#                },
#                "age":{
#                   "type":"integer"
#                }
#             },
#             "required":[
#                :"name",
#                :"age"
#             ],
#             "additionalProperties":false
#          },
#          "employees":{
#             "type":"array",
#             "items":{
#                "type":"object",
#                "properties":{
#                   "name":{
#                      "type":"string"
#                   },
#                   "age":{
#                      "type":"integer"
#                   }
#                },
#                "required":[
#                   :"name",
#                   :"age"
#                ],
#                "additionalProperties":false
#             }
#          },
#          "founder":{
#             "type":"object",
#             "properties":{
#                "name":{
#                   "type":"string"
#                },
#                "age":{
#                   "type":"integer"
#                }
#             },
#             "required":[
#                :"name",
#                :"age"
#             ],
#             "additionalProperties":false
#          }
#       },
#       "required":[
#          :"ceo",
#          :"employees",
#          :"founder"
#       ],
#       "additionalProperties":false,
#       "strict":true
#    }
# }
```

## JSON Output

```ruby
schema = PersonSchema.new
schema.to_json_schema
# => {
#   name: "PersonSchema",
#   description: nil,
#   schema: {
#     type: "object",
#     properties: { ... },
#     required: [...],
#     additionalProperties: false,
#     strict: true
#   }
# }

puts schema.to_json  # Pretty JSON string
```

## Schema Compression

When sending schemas to LLMs, long field names consume tokens. The compression feature replaces field names with short codes based on the first letter of each field name, using two letters only when there are conflicts. This keeps compressed names intuitive while significantly reducing token usage.

### Basic Usage

```ruby
class UserSchema < RubyLLM::Schema
  string :first_name, description: "User's first name"
  string :last_name, description: "User's last name"
  integer :age
  object :address do
    string :street
    string :city
    string :zip_code
  end
end

schema = UserSchema.new("User")
result = schema.to_json_schema(compress: true)
```

The compressed schema transforms field names using first letters:
- `first_name` → `f`
- `last_name` → `l`
- `age` → `a`
- `address` → `ad` (conflict with `age`)
- `address.street` → `s`
- `address.city` → `c`
- `address.zip_code` → `z`

Original field names are preserved in descriptions:
```json
{
  "f": { "type": "string", "description": "first_name: User's first name" },
  "l": { "type": "string", "description": "last_name: User's last name" },
  "a": { "type": "integer", "description": "age" }
}
```

### Expanding Responses

When an LLM returns a response with compressed field names, use the `Expander` to restore original names:

```ruby
# Get compressed schema with field_map
result = schema.to_json_schema(compress: true)
compressed_schema = result[:schema]
field_map = result[:field_map]

# ... send compressed_schema to LLM and get response ...

# LLM response uses compressed field names
llm_response = {
  "f" => "John",
  "l" => "Doe",
  "a" => 30,
  "ad" => {
    "s" => "123 Main St",
    "c" => "Springfield",
    "z" => "12345"
  }
}

# Expand back to original field names
expanded = RubyLLM::Schema::Expander.expand(llm_response, field_map)
# => {
#   first_name: "John",
#   last_name: "Doe",
#   age: 30,
#   address: {
#     street: "123 Main St",
#     city: "Springfield",
#     zip_code: "12345"
#   }
# }
```

### Integration with ruby_llm

When using the `ruby_llm` gem, you can integrate compression like this:

```ruby
class UserSchema < RubyLLM::Schema
  string :first_name, description: "User's first name"
  string :last_name
  integer :age
end

# Get compressed schema
schema = UserSchema.new("User")
compressed = schema.to_json_schema(compress: true)

# Use with ruby_llm
response = RubyLLM.chat(
  model: "gpt-4",
  messages: [{ role: "user", content: "Extract user info from: John Doe, 30 years old" }],
  response_format: compressed  # Pass the compressed schema
)

# Parse and expand the response
parsed = JSON.parse(response.content, symbolize_names: false)
expanded = RubyLLM::Schema::Expander.expand(parsed, compressed[:field_map])

puts expanded[:first_name]  # => "John"
puts expanded[:last_name]   # => "Doe"
puts expanded[:age]         # => 30
```

### Options

```ruby
# Get string keys instead of symbols
expanded = RubyLLM::Schema::Expander.expand(response, field_map, symbolize: false)
# => { "first_name" => "John", "last_name" => "Doe", "age" => 30 }
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
