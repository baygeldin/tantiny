# frozen_string_literal: true

module Tantiny
  class Tokenizer
    def self.default
      new(:simple)
    end

    def self.new(kind, **options)
      case kind
      when :simple
        __new_simple_tokenizer
      when :stemmer
        language = options[:language] || :en
        __new_stemmer_tokenizer(language.to_s)
      when :ngram
        prefix_only = options.fetch(:prefix_only, false)
        __new_ngram_tokenizer(options[:min], options[:max], prefix_only)
      else
        raise UnknownTokenizer.new(kind)
      end
    end

    def terms(string)
      __extract_terms(string)
    end
  end
end
