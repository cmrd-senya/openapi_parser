require_relative '../../spec_helper'
require 'active_support'
require 'active_support/core_ext'

RSpec.describe OpenAPIParser::SchemaValidator::ObjectValidator do
  let(:value) do
    {}
  end

  let(:schema_validator) do
    OpenAPIParser::SchemaValidator.new(
      value,
      root,
      OpenAPIParser::SchemaValidator::Options.new
    )
  end

  let(:schema) do
    {
      'openapi' => '3.0.0',
      'components' => {
        'schemas' => {
          'object_with_required_but_no_properties' => {
            'type' => 'object',
            'required' => ['id'],
          },
        },
      }
    }
  end

  let(:root) do
    OpenAPIParser.parse(schema)
  end

  before do
    #binding.pry
    @validator = OpenAPIParser::SchemaValidator::ObjectValidator.new(schema_validator, nil)
  end

  it 'shows error when required key is absent' do
    schema = root.components.schemas['object_with_required_but_no_properties']
    _value, errors = *@validator.coerce_and_validate({}, schema)

    e = errors.first
    expect(e&.message).to match('.* missing required parameters: id')
  end

  context 'complex object' do
    let(:value) do
      { 'foo' => {} }
    end
    let(:schema_validator) do
      OpenAPIParser::SchemaValidator.new(
        value,
        root.paths.path['/nested_object'].operation(:post).request_body.content['application/json'].schema,
        OpenAPIParser::SchemaValidator::Options.new
      )
    end

    let(:schema) do
      {
        'openapi' => '3.0.0',
        'paths' => {
          '/nested_object': {
            post: {
              requestBody: {
                content: {
                  'application/json': {
                    schema: {
                      type: 'object',
                      properties: {
                        id: {
                          type: 'integer'
                        },
                        foo: {
                          type: 'object',
                          required: %w[bar baz],
                          properties: {
                            bar: { type: 'string' },
                            baz: { type: 'string' }
                          }
                        }
                      },
                      required: %w[id foo]
                    }
                  }
                }
              },
              responses: {
                '200': {
                  content: {
                    'application/json': {
                      schema: {
                        type: 'object',
                        properties: {
                          my_name: {
                            type: 'string',
                            nullable: false
                          }
                        },
                        required: [
                          'my_name'
                        ]
                      }
                    }
                  }
                }
              }
            }
          }
        },
        'components' => {
          'schemas' => {
            'object_with_required_but_no_properties' => {
              'type' => 'object',
              'required' => ['id', 'foo'],
              'properties' => {
                'foo' => {
                  'type' => 'object',
                  'required' => ['bar', 'baz']
                }
              }
            },
          },
        }
      }.deep_stringify_keys
    end

    it 'shows error when required key is absent on different nesting levels' do
      # binding.pry
      schema_validator.validate_data
      # schema = root.components.schemas['object_with_required_but_no_properties']
      # _value, e = *@validator.coerce_and_validate({'foo' => {}}, schema)
      rescue => e

        #binding.pry
      # expect(e&.message).to match('.* missing required parameters: id')
    end
  end
end

RSpec.describe OpenAPIParser::Schemas::RequestBody do


  describe 'object properties' do
    context 'discriminator check' do
      let(:content_type) { 'application/json' }
      let(:http_method) { :post }
      let(:request_path) { '/save_the_pets' }
      let(:request_operation) { root.request_operation(http_method, request_path) }
      let(:params) { {} }
      let(:root) { OpenAPIParser.parse(petstore_with_discriminator_schema, {}) }

      it 'throws error when sending unknown property key with no additionalProperties defined' do
        body = {
            "baskets" => [
                {
                    "name"    => "cats",
                    "content" => [
                        {
                            "name"        => "Mr. Cat",
                            "born_at"     => "2019-05-16T11:37:02.160Z",
                            "description" => "Cat gentleman",
                            "milk_stock"  => 10,
                            "unknown_key" => "value"
                        }
                    ]
                },
            ]
        }

        expect { request_operation.validate_request_body(content_type, body) }.to raise_error do |e|
          expect(e).to be_kind_of(OpenAPIParser::NotExistPropertyDefinition)
          expect(e.message).to end_with("does not define properties: unknown_key")
        end
      end

      it 'throws error when sending multiple unknown property keys with no additionalProperties defined' do
        body = {
            "baskets" => [
                {
                    "name"    => "cats",
                    "content" => [
                        {
                            "name"                => "Mr. Cat",
                            "born_at"             => "2019-05-16T11:37:02.160Z",
                            "description"         => "Cat gentleman",
                            "milk_stock"          => 10,
                            "unknown_key"         => "value",
                            "another_unknown_key" => "another_value"
                        }
                    ]
                },
            ]
        }

        expect { request_operation.validate_request_body(content_type, body) }.to raise_error do |e|
          expect(e).to be_kind_of(OpenAPIParser::NotExistPropertyDefinition)
          expect(e.message).to end_with("does not define properties: unknown_key, another_unknown_key")
        end
      end

      it 'ignores unknown property key if additionalProperties is defined' do
        # TODO: we have to use additional properties to do the validation
        body = {
            "baskets" => [
                {
                    "name"    => "squirrels",
                    "content" => [
                        {
                            "name"        => "Mrs. Squirrel",
                            "born_at"     => "2019-05-16T11:37:02.160Z",
                            "description" => "Squirrel superhero",
                            "nut_stock"   => 10,
                            "unknown_key" => "value"
                        }
                    ]
                },
            ]
        }

        request_operation.validate_request_body(content_type, body)
      end

      it 'throws error when sending nil disallowed in allOf' do
        body = {
            "baskets" => [
                {
                    "name"    => "turtles",
                    "content" => [
                        {
                            "name"                  => "Mr. Cat",
                            "born_at"               => "2019-05-16T11:37:02.160Z",
                            "description"           => "Cat gentleman",
                            "required_combat_style" => nil,
                        }
                    ]
                },
            ]
        }

        expect { request_operation.validate_request_body(content_type, body) }.to raise_error do |e|
          expect(e).to be_kind_of(OpenAPIParser::NotNullError)
          expect(e.message).to end_with("does not allow null values")
        end
      end

      it 'passing when sending nil nested to anyOf that is allowed' do
        body = {
            "baskets" => [
                {
                    "name"    => "turtles",
                    "content" => [
                        {
                            "name"                  => "Mr. Cat",
                            "born_at"               => "2019-05-16T11:37:02.160Z",
                            "description"           => "Cat gentleman",
                            "optional_combat_style" => nil,
                        }
                    ]
                },
            ]
        }

        request_operation.validate_request_body(content_type, body)
      end

      it 'throws error when unknown attribute nested in allOf' do
        body = {
            "baskets" => [
                {
                    "name"    => "turtles",
                    "content" => [
                        {
                            "name"                  => "Mr. Cat",
                            "born_at"               => "2019-05-16T11:37:02.160Z",
                            "description"           => "Cat gentleman",
                            "required_combat_style" => {
                                "bo_color"              => "brown",
                                "grappling_hook_length" => 10.2
                            },
                        }
                    ]
                },
            ]
        }

        expect { request_operation.validate_request_body(content_type, body) }.to raise_error do |e|
          expect(e.kind_of?(OpenAPIParser::NotAnyOf)).to eq true
          expect(e.message).to match("^.*?(isn't any of).*?$")
        end
      end

      it 'passes error with correct attributes nested in allOf' do
        body = {
            "baskets" => [
                {
                    "name"    => "turtles",
                    "content" => [
                        {
                            "name"                  => "Mr. Cat",
                            "born_at"               => "2019-05-16T11:37:02.160Z",
                            "description"           => "Cat gentleman",
                            "required_combat_style" => {
                                "bo_color"       => "brown",
                                "shuriken_count" => 10
                            },
                        }
                    ]
                },
            ]
        }

        request_operation.validate_request_body(content_type, body)
      end

      it 'throws error when unknown attribute nested in allOf' do
        body = {
            "baskets" => [
                {
                    "name"    => "turtles",
                    "content" => [
                        {
                            "name"                  => "Mr. Cat",
                            "born_at"               => "2019-05-16T11:37:02.160Z",
                            "description"           => "Cat gentleman",
                            "optional_combat_style" => {
                                "bo_color"              => "brown",
                                "grappling_hook_length" => 10.2
                            },
                        }
                    ]
                },
            ]
        }

        expect { request_operation.validate_request_body(content_type, body) }.to raise_error do |e|
          expect(e.kind_of?(OpenAPIParser::NotAnyOf)).to eq true
          expect(e.message).to match("^.*?(isn't any of).*?$")
        end
      end

      it 'passes error with correct attributes nested in anyOf' do
        body = {
            "baskets" => [
                {
                    "name"    => "turtles",
                    "content" => [
                        {
                            "name"                  => "Mr. Cat",
                            "born_at"               => "2019-05-16T11:37:02.160Z",
                            "description"           => "Cat gentleman",
                            "optional_combat_style" => {
                                "bo_color"       => "brown",
                                "shuriken_count" => 10
                            },
                        }
                    ]
                },
            ]
        }

        request_operation.validate_request_body(content_type, body)
      end
    end

    context 'additional_properties check' do
      subject { request_operation.validate_request_body(content_type, JSON.load(params.to_json)) }

      let(:root) { OpenAPIParser.parse(schema, {}) }
      let(:schema) { build_validate_test_schema(replace_schema) }

      let(:content_type) { 'application/json' }
      let(:http_method) { :post }
      let(:request_path) { '/validate_test' }
      let(:request_operation) { root.request_operation(http_method, request_path) }
      let(:params) { {} }

      context 'no additional_properties' do
        let(:replace_schema) do
          {
              query_string: {
                  type: 'string',
              },
          }
        end
        let(:params) { { 'query_string' => 'query' } }
        it { expect(subject).to eq({ 'query_string' => 'query'}) }

      end

      context 'additional_properties = default' do
        let(:replace_schema) do
          {
              query_string: {
                  type: 'string',
              },
          }
        end
        let(:params) { { 'query_string' => 'query', 'unknown' => 1 } }

        it { expect(subject).to eq({ 'query_string' => 'query', 'unknown' => 1 }) }
      end

      context 'additional_properties = false' do
        let(:schema) do
          s = build_validate_test_schema(replace_schema)
          obj = s['paths']['/validate_test']['post']['requestBody']['content']['application/json']['schema']
          obj['additionalProperties'] = { 'type' => 'string' }
          s
        end

        let(:replace_schema) do
          {
              query_string: {
                  type: 'string',
              },
          }
        end

        let(:params) { { 'query_string' => 'query', 'unknown' => 1 } }
        # TODO: we need to perform a validation based on schema.additional_properties here, if
        it { expect(params).to eq({ 'query_string' => 'query', 'unknown' => 1 }) }
      end
    end
  end
end
