# frozen_string_literal: true

require "date"

module Tantiny
  class Query
    TYPES = %i[
      all empty term fuzzy_term
      phrase regex range facet
      smart prefix
    ].freeze

    DEFAULT_BOOST = 1.0
    DEFAULT_FUZZY_DISTANCE = 1

    class << self
      def conjunction(*queries)
        # @type var queries: Array[untyped]
        queries.one? ? queries.first : __conjunction(queries)
      end

      def disjunction(*queries)
        # @type var queries: Array[untyped]
        queries.one? ? queries.first : __disjunction(queries)
      end

      def all_query(_index = nil)
        __new_all_query
      end

      def empty_query(_index = nil)
        __new_empty_query
      end

      def term_query(index, fields, term, **)
        allowed_fields = text_and_strings(index)
        construct_query(index, :term, allowed_fields, fields, [term.to_s], **)
      end

      def fuzzy_term_query(index, fields, term, distance = DEFAULT_FUZZY_DISTANCE, **)
        params = [term.to_s, distance.to_i]
        allowed_fields = text_and_strings(index)
        construct_query(index, :fuzzy_term, allowed_fields, fields, params, **)
      end

      def phrase_query(index, fields, phrase, **)
        queries = [*fields].map do |f|
          terms = index.schema.tokenizer_for(f).terms(phrase)
          allowed_fields = index.schema.text_fields
          construct_query(index, :phrase, allowed_fields, f, [terms], **)
        end

        queries.empty? ? empty_query : disjunction(*queries)
      end

      def regex_query(index, fields, regex, **)
        allowed_fields = text_and_strings(index)
        construct_query(index, :regex, allowed_fields, fields, [regex.to_s], **)
      end

      def prefix_query(index, fields, prefix, **)
        regex_query(index, fields, Regexp.escape(prefix) + ".*", **)
      end

      def range_query(index, fields, range, **)
        schema = index.schema

        case range.first
        when Integer
          allowed_fields = schema.integer_fields
          from, to = [range.min, range.max]
        when Float
          allowed_fields = schema.double_fields
          from, to = [range.first, range.last]
        when Date, DateTime
          # @type var range: Range[Date | DateTime]
          allowed_fields = schema.date_fields
          from, to = [Helpers.timestamp(range.first), Helpers.timestamp(range.last)]
        else
          raise UnsupportedRange.new(range.first.class)
        end

        # @type var allowed_fields: Array[Symbol]
        construct_query(index, :range, allowed_fields, fields, [from, to], **)
      end

      def facet_query(index, field, path, **)
        allowed_fields = index.schema.facet_fields
        construct_query(index, :facet, allowed_fields, field, [path], **)
      end

      def smart_query(index, fields, query_string, **options)
        fuzzy_distance = options[:fuzzy_distance]
        boost_factor = options.fetch(:boost, DEFAULT_BOOST)

        field_queries = [*fields].filter_map do |field|
          terms = index.schema.tokenizer_for(field).terms(query_string)

          # See: https://github.com/soutaro/steep/issues/272
          # @type block: nil | Query
          next if terms.empty?

          term_queries = terms.map do |term|
            if fuzzy_distance.nil?
              term_query(index, field, term)
            else
              fuzzy_term_query(index, field, term, fuzzy_distance)
            end
          end

          # @type var terms: untyped
          # @type var term_queries: untyped
          last_term_query = prefix_query(index, field, terms.last) | term_queries.last

          conjunction(last_term_query, *term_queries[0...-1])
        end

        disjunction(*field_queries).boost(boost_factor)
      end

      def highlight(text, query_string, fuzzy_distance: 0, tokenizer: Tantiny::Tokenizer.new(:simple))
        terms = tokenizer.terms(query_string).map(&:to_s)
        __highlight(text.to_s, terms, fuzzy_distance)
      end

      private

      # Can't use variadic argument `params` here due to:
      # https://github.com/soutaro/steep/issues/480
      def construct_query(index, query_type, allowed_fields, fields, params, **options)
        queries = [*fields].map do |field|
          supported = allowed_fields.include?(field)
          raise UnsupportedField.new(field) unless supported

          send("__new_#{query_type}_query", index, field.to_s, *params)
        end

        return empty_query if fields.empty?

        disjunction(*queries).boost(options.fetch(:boost, DEFAULT_BOOST))
      end

      def text_and_strings(index)
        index.schema.text_fields | index.schema.string_fields
      end
    end

    def |(other)
      raise ArgumentError.new("Not a #{self.class}.") unless other.is_a?(self.class)

      self.class.disjunction(self, other)
    end

    def &(other)
      raise ArgumentError.new("Not a #{self.class}.") unless other.is_a?(self.class)

      self.class.conjunction(self, other)
    end

    def !
      __negation
    end

    def boost(boost_factor)
      return self if boost_factor == DEFAULT_BOOST

      __boost(boost_factor.to_f)
    end
  end
end
