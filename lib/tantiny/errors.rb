# frozen_string_literal: true

module Tantiny
  class TantivyError < StandardError; end

  class IndexWriterBusyError < StandardError
    def initialize
      msg = "Failed to acquire an index writer. " \
        "Is there an active index with an exclusive writer already?"

      super(msg)
    end
  end

  class UnexpectedNone < StandardError
    def initialize(type)
      super("Didn't expect Option<#{type}> to be empty.")
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
