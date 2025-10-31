# frozen_string_literal: true

RSpec.describe Tantiny::Index do
  subject(:index) do
    Tantiny::Index.new(tmpdir, **options, &schema_block)
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:options) { {tokenizer: tokenizer} }
  let(:schema_block) { proc {} }
  let(:tokenizer) { Tantiny::Tokenizer.default }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def documents
    index.search(index.all_query)
  end

  describe "panics" do
    it "doesn't panic when Option<T> is None" do
      # This test verifies that unknown fields are handled gracefully
      # rather than causing a Rust panic
      index.transaction do
        expect {
          index.__add_document("tmp", {"unkown_field" => "whatever"}, {}, {}, {}, {}, {})
        }.to raise_error(RuntimeError, /Failed to get field/)
      end
    end
  end

  describe "::new" do
    context "when path is provided" do
      it "creates index at path" do
        Tantiny::Index.new(tmpdir) {}
        expect(Dir.entries(tmpdir)).not_to be_empty
      end

      context "when folder at path does not exist" do
        it "creates it first" do
          FileUtils.rm_rf(tmpdir)
          expect { Tantiny::Index.new(tmpdir) {} }.not_to raise_error
          expect(Dir.entries(tmpdir)).not_to be_empty
        end
      end
    end

    context "when no path is provided" do
      it "creates an in-memory index" do
        index = Tantiny::Index.new { text :title }
        expect(index.in_memory?).to be true
      end

      it "can add and search documents" do
        index = Tantiny::Index.new { text :title }
        index << {id: "1", title: "Test Document"}
        index.reload
        results = index.search(index.all_query)
        expect(results).to eq(["1"])
      end

      it "does not use file locking" do
        index = Tantiny::Index.new { text :title }
        expect(Tantiny::Helpers).not_to receive(:with_lock)
        index << {id: "1", title: "Test"}
      end
    end

    it "creates schema" do
      schema = Tantiny::Schema.new(tokenizer, &schema_block)

      expect(Tantiny::Schema).to receive(:new)
        .with(tokenizer, &schema_block).and_return(schema)

      index = Tantiny::Index.new(tmpdir, tokenizer: tokenizer, &schema_block)

      expect(index.schema).to eq(schema)
    end

    context "when exclusive_writer is true" do
      let(:options) { {exclusive_writer: true} }

      it "doesn't need to acquire an index writer on every change" do
        expect(index).not_to receive(:acquire_index_writer)

        index << {id: 1}
        index << {id: 2}
      end
    end
  end

  describe ".transaction" do
    let(:mutex) { index.instance_variable_get(:@transaction_semaphore) }

    it "synchronizes block execution between threads" do
      collaborator_1 = double("Collaborator 1")
      collaborator_2 = double("Collaborator 2")

      allow(mutex).to receive(:synchronize) do |&block|
        collaborator_1.enter_mutex
        block.call
        collaborator_1.leave_mutex
      end

      expect(collaborator_1).to receive(:enter_mutex).ordered
      expect(collaborator_2).to receive(:hello).ordered
      expect(collaborator_1).to receive(:leave_mutex).ordered

      index.transaction { collaborator_2.hello }
    end

    it "synchronizes block execution between processes" do
      collaborator_1 = double("Collaborator 1")
      collaborator_2 = double("Collaborator 2")

      allow(Tantiny::Helpers).to receive(:with_lock) do |&block|
        collaborator_1.lock
        block.call
        collaborator_1.unlock
      end

      expect(collaborator_1).to receive(:lock).ordered
      expect(collaborator_2).to receive(:hello).ordered
      expect(collaborator_1).to receive(:unlock).ordered

      index.transaction { collaborator_2.hello }
    end

    context "when inside a transaction" do
      it "simply executes the block without synchronization" do
        collaborator = double("Collaborator")

        expect(mutex).to receive(:synchronize).and_call_original.once
        expect(collaborator).to receive(:hello)

        index.transaction do
          index.transaction { collaborator.hello }
        end
      end
    end

    context "when another index holds exclusive writer" do
      it "raises an error" do
        collaborator = double("Collaborator")

        Tantiny::Index.new(tmpdir, exclusive_writer: true, &schema_block)

        expect {
          index.transaction { collaborator.hello }
        }.to raise_error(Tantiny::IndexWriterBusyError)
      end
    end

    it "commits the changes" do
      index.transaction { index << {id: "hello"} }
      index.reload

      expect(index.search(index.all_query)).to contain_exactly("hello")
    end
  end

  describe ".<<" do
    let(:schema_block) do
      proc do
        id :imdb_id
        facet :category
        string :title
        text :description
        double :rating
        integer :duration
        date :release_date
      end
    end

    let(:movie) do
      {
        imdb_id: "tt0119250",
        title: "Hana-bi",
        description: "Takeshi Kitano goes bonkers.",
        category: ["/crime/Japan", "/crime/Shinjuku"],
        duration: 103,
        rating: 7.7,
        release_date: Date.parse("December 1, 1998")
      }
    end

    it "maps fields according to schema" do
      index << movie
      index.reload

      imdb_id = movie[:imdb_id]

      string_query = index.term_query(:title, "Hana-bi")
      text_query = index.term_query(:description, "bonkers")
      facet_query = index.facet_query(:category, "/crime")
      integer_query = index.range_query(:duration, 100..150)
      double_query = index.range_query(:rating, 7.0..10.0)
      date_query = index.range_query(:release_date, Date.new(1900)..Date.new(2000))

      expect(index.search(string_query).first).to eq(imdb_id)
      expect(index.search(text_query).first).to eq(imdb_id)
      expect(index.search(facet_query).first).to eq(imdb_id)
      expect(index.search(integer_query).first).to eq(imdb_id)
      expect(index.search(double_query).first).to eq(imdb_id)
      expect(index.search(date_query).first).to eq(imdb_id)
    end

    it "allows empty fields" do
      index << movie.slice(:imdb_id, :title)
      index.reload

      query = index.term_query(:title, "Hana-bi")

      expect(index.search(query).first).to eq(movie[:imdb_id])
    end

    it "works with any object" do
      index << OpenStruct.new(movie)
      index.reload

      query = index.term_query(:title, "Hana-bi")

      expect(index.search(query).first).to eq(movie[:imdb_id])
    end

    it "wraps itself in a transaction" do
      expect(index).to receive(:transaction).and_call_original

      index << movie
      index.reload

      expect(index.search(index.all_query)).not_to be_empty
    end
  end

  describe ".reload" do
    it "reloads the index" do
      index << {id: 1}

      expect { index.reload }.to change { documents }.from([]).to(%w[1])
    end
  end

  describe ".delete" do
    it "deletes an already commited document" do
      index << {id: "kek"}
      index.reload

      expect {
        index.delete("kek")
        index.reload
      }.to change { documents }.from(%w[kek]).to([])
    end

    it "deletes uncommited document" do
      index << {id: "kek"}
      index.delete("kek")
      index.reload

      expect(documents).to be_empty
    end

    it "wraps itself in a transaction" do
      index << {id: "kek"}

      expect(index).to receive(:transaction).and_call_original

      index.delete("kek")
      index.reload

      expect(index.search(index.all_query)).to be_empty
    end
  end

  describe ".search" do
    let(:schema_block) { proc { text :description } }

    before do
      index.transaction do
        (1..10).each { |id| index << {id: id, description: "hello"} }
      end

      index.reload
    end

    context "when query is a query object" do
      let(:query) { index.all_query }

      it "executes the query" do
        expect(index.search(query).length).to be(10)
      end

      it "takes limit into account" do
        expect(index.search(query, limit: 2).length).to be(2)
      end
    end

    context "when query is a string" do
      it "creates a smart query for all text fields" do
        fields = index.schema.text_fields
        query_string = "hellp"
        smart_query_options = {fuzzy_distance: 1}
        query = Tantiny::Query.smart_query(index, fields, query_string, **smart_query_options)

        expect(Tantiny::Query).to receive(:smart_query)
          .with(index, fields, query_string, **smart_query_options).and_return(query)

        expect(index.search(query_string, **smart_query_options).length).to be(10)
      end

      it "takes limit into account" do
        expect(index.search("hello", limit: 2).length).to be(2)
      end
    end
  end

  Tantiny::Query::TYPES.each do |query_type|
    method_name = "#{query_type}_query"
    describe ".#{method_name}" do
      it "forwards args to Query" do
        any_args = [1, 2, 3]
        any_kwargs = {foo: :bar}

        expect(Tantiny::Query).to receive(method_name).with(index, *any_args, **any_kwargs)

        index.send(method_name, *any_args, **any_kwargs)
      end
    end
  end
end
