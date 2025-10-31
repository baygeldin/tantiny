# frozen_string_literal: true

module Tantiny
  class Index
    LOCKFILE = ".tantiny.lock"
    DEFAULT_WRITER_MEMORY = 15_000_000 # 15MB
    DEFAULT_LIMIT = 10

    def self.new(path = nil, **options, &)
      # Only create directory if path is provided
      FileUtils.mkdir_p(path) if path

      default_tokenizer = options[:tokenizer] || Tokenizer.default
      schema = Schema.new(default_tokenizer, &)

      object = __new(
        path&.to_s,
        schema.default_tokenizer,
        schema.field_tokenizers.transform_keys(&:to_s),
        schema.text_fields.map(&:to_s),
        schema.string_fields.map(&:to_s),
        schema.integer_fields.map(&:to_s),
        schema.double_fields.map(&:to_s),
        schema.date_fields.map(&:to_s),
        schema.facet_fields.map(&:to_s)
      )

      object.send(:initialize, path, schema, **options)

      object
    end

    def initialize(path, schema, **options)
      @path = path
      @schema = schema

      @indexer_memory = options[:writer_memory] || DEFAULT_WRITER_MEMORY
      @exclusive_writer = options[:exclusive_writer] || false

      @active_transaction = Concurrent::ThreadLocalVar.new(false)
      @transaction_semaphore = Mutex.new

      acquire_index_writer if exclusive_writer?
    end

    attr_reader :schema

    def in_memory?
      @path.nil?
    end

    def transaction
      if inside_transaction?
        yield
      else
        synchronize do
          open_transaction!

          yield

          close_transaction!
        end
      end

      nil
    end

    def reload
      __reload
    end

    def <<(document)
      transaction do
        __add_document(
          resolve(document, schema.id_field).to_s,
          slice_document(document, schema.text_fields) { |v| v.is_a?(Array) ? v.map(&:to_s) : v.to_s },
          slice_document(document, schema.string_fields) { |v| v.is_a?(Array) ? v.map(&:to_s) : v.to_s },
          slice_document(document, schema.integer_fields) { |v| v.is_a?(Array) ? v.map(&:to_i) : v.to_i },
          slice_document(document, schema.double_fields) { |v| v.is_a?(Array) ? v.map(&:to_f) : v.to_f },
          slice_document(document, schema.date_fields) { |v| v.is_a?(Array) ? v.map { |d| Helpers.timestamp(d) } : Helpers.timestamp(v) },
          slice_document(document, schema.facet_fields) { |v| v.is_a?(Array) ? v.map(&:to_s) : v.to_s }
        )
      end
    end

    def delete(id)
      transaction do
        __delete_document(id.to_s)
      end
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
        Query.send(method_name, self, *args, **kwargs)
      end
    end

    private

    def slice_document(document, fields, &)
      fields.inject({}) do |hash, field|
        hash.tap { |h| h[field.to_s] = resolve(document, field) }
      end.compact.transform_values(&)
    end

    def resolve(document, field)
      document.is_a?(Hash) ? document[field] : document.send(field)
    end

    def acquire_index_writer
      __acquire_index_writer(@indexer_memory)
    rescue RuntimeError => e
      case e.message
      when /Failed to acquire Lockfile/, /LockBusy/
        raise IndexWriterBusyError.new
      else
        raise
      end
    end

    def release_index_writer
      __release_index_writer
    end

    def commit
      __commit
    end

    def open_transaction!
      acquire_index_writer unless exclusive_writer?

      @active_transaction.value = true
    end

    def close_transaction!
      commit

      release_index_writer unless exclusive_writer?

      @active_transaction.value = false
    end

    def inside_transaction?
      @active_transaction.value
    end

    def exclusive_writer?
      @exclusive_writer
    end

    def synchronize(&)
      # In-memory indexes don't need file locking
      if in_memory?
        @transaction_semaphore.synchronize(&)
      else
        @transaction_semaphore.synchronize do
          Helpers.with_lock(lockfile_path, &)
        end
      end
    end

    def lockfile_path
      @lockfile_path ||= @path && File.join(@path, LOCKFILE)
    end
  end
end
