# frozen_string_literal: true

module Tantiny
  class TantivyError < StandardError; end

  class UnknownField < StandardError
    def initialize
      super("Can't find the specified field in the schema.")
    end
  end

  class UnknownTokenizer < StandardError
    def initialize(tokenizer_type)
      super("Can't find \"#{tokenizer_type}\" tokenizer.")
    end
  end

  class UnsupportedRange < StandardError
    def initialize(range_type)
      super("#{range_type} range is not supported by range_query.")
    end
  end

  class UnsupportedField < StandardError
    def initialize(field)
      super("Can't search the \"#{field}\" field with this query.")
    end
  end
end
