# frozen_string_literal: true

require "fileutils"

module Tantiny
  class Index
    DEFAULT_INDEX_SIZE = 50_000_000
    DEFAULT_LIMIT = 10

    def self.new(path, **options, &block)
      index_size = options[:size] || DEFAULT_INDEX_SIZE
      default_tokenizer = options[:tokenizer] || Tokenizer.default

      FileUtils.mkdir_p(path)

      schema = Schema.new(default_tokenizer, &block)

      object = __new(
        path.to_s,
        index_size,
        schema.default_tokenizer,
        schema.field_tokenizers.transform_keys(&:to_s),
        schema.text_fields.map(&:to_s),
        schema.string_fields.map(&:to_s),
        schema.integer_fields.map(&:to_s),
        schema.double_fields.map(&:to_s),
        schema.date_fields.map(&:to_s),
        schema.facet_fields.map(&:to_s)
      )

      object.send(:schema=, schema)

      object
    end

    attr_reader :schema

    def commit
      __commit
    end

    def reload
      __reload
    end

    def <<(document)
      __add_document(
        resolve(document, schema.id_field).to_s,
        slice_document(document, schema.text_fields) { |v| v.to_s },
        slice_document(document, schema.string_fields) { |v| v.to_s },
        slice_document(document, schema.integer_fields) { |v| v.to_i },
        slice_document(document, schema.double_fields) { |v| v.to_f },
        slice_document(document, schema.date_fields) { |v| Helpers.timestamp(v) },
        slice_document(document, schema.facet_fields) { |v| v.to_s }
      )
    end

    def delete(id)
      __delete_document(id.to_s)
    end

    def search(query, limit: DEFAULT_LIMIT, **smart_query_options)
      unless query.is_a?(Query)
        fields = schema.text_fields
        query = Query.smart_query(self, fields, query.to_s, **smart_query_options)
      end

      __search(query, limit)
    end

    # Shortcuts for creating queries:
    Query::TYPES.each do |query_type|
      method_name = "#{query_type}_query"
      define_method(method_name) do |*args, **kwargs|
        # Ruby 2.6 fix (https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/)
        if kwargs.empty?
          Query.send(method_name, self, *args)
        else
          Query.send(method_name, self, *args, **kwargs)
        end
      end
    end

    private

    attr_writer :schema

    def slice_document(document, fields, &block)
      fields.inject({}) do |hash, field|
        hash.tap { |h| h[field.to_s] = resolve(document, field) }
      end.compact.transform_values(&block)
    end

    def resolve(document, field)
      document.is_a?(Hash) ? document[field] : document.send(field)
    end
  end
end
