# frozen_string_literal: true

module Tantiny
  class Schema
    attr_reader :default_tokenizer,
      :id_field,
      :text_fields,
      :string_fields,
      :integer_fields,
      :double_fields,
      :date_fields,
      :facet_fields,
      :field_tokenizers

    def initialize(tokenizer, &)
      @default_tokenizer = tokenizer
      @id_field = :id
      @text_fields = []
      @string_fields = []
      @integer_fields = []
      @double_fields = []
      @date_fields = []
      @facet_fields = []
      @field_tokenizers = {}

      instance_exec(&)
    end

    def tokenizer_for(field)
      field_tokenizers[field] || default_tokenizer
    end

    private

    def id(key) = @id_field = key

    def string(key) = @string_fields << key

    def integer(key) = @integer_fields << key

    def double(key) = @double_fields << key

    def date(key) = @date_fields << key

    def facet(key) = @facet_fields << key

    def text(key, tokenizer: nil)
      @field_tokenizers[key] = tokenizer if tokenizer

      @text_fields << key
    end
  end
end
