# frozen_string_literal: true

RSpec.describe Tantiny::Index do
  subject(:index) do
    Tantiny::Index.new(tmpdir, tokenizer: tokenizer, &schema_block)
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:schema_block) { proc {} }
  let(:tokenizer) { Tantiny::Tokenizer.default }

  after do
    FileUtils.remove_dir(tmpdir)
  end

  def documents
    index.search(index.all_query)
  end

  def commit_and_reload
    index.commit
    index.reload
  end

  describe "::new" do
    it "creates index at path" do
      Tantiny::Index.new(tmpdir) {}
      expect(Dir.entries(tmpdir)).not_to be_empty
    end

    it "creates schema" do
      schema = Tantiny::Schema.new(tokenizer, &schema_block)

      expect(Tantiny::Schema).to receive(:new)
        .with(tokenizer, &schema_block).and_return(schema)

      index = Tantiny::Index.new(tmpdir, tokenizer: tokenizer, &schema_block)

      expect(index.schema).to eq(schema)
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
        category: "/crime/Japan",
        duration: 103,
        rating: 7.7,
        release_date: Date.parse("December 1, 1998")
      }
    end

    it "maps fields according to schema" do
      index << movie
      commit_and_reload

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
      commit_and_reload

      query = index.term_query(:title, "Hana-bi")

      expect(index.search(query).first).to eq(movie[:imdb_id])
    end

    it "works with any object" do
      index << OpenStruct.new(movie)
      commit_and_reload

      query = index.term_query(:title, "Hana-bi")

      expect(index.search(query).first).to eq(movie[:imdb_id])
    end

    it "raises error for unkown fields" do
      expect {
        # Currently this is the only way to cause the error.
        index.__add_document("tmp", {"unkown_field" => "whatever"}, {}, {}, {}, {}, {})
      }.to raise_error(Tantiny::UnknownField)
    end
  end

  describe ".commit" do
    it "commits the index" do
      index << {id: 1}

      expect { index.commit }.not_to raise_error
    end
  end

  describe ".reload" do
    it "reloads the index" do
      index << {id: 1}
      index.commit

      expect { index.reload }.to change { documents }.from([]).to(%w[1])
    end
  end

  describe ".delete" do
    it "deletes an already commited document" do
      index << {id: "kek"}
      commit_and_reload

      expect {
        index.delete("kek")
        commit_and_reload
      }.to change { documents }.from(%w[kek]).to([])
    end

    it "deletes uncommited document" do
      index << {id: "kek"}
      index.delete("kek")
      commit_and_reload

      expect(documents).to be_empty
    end
  end

  describe ".search" do
    let(:schema_block) { proc { text :description } }

    before do
      (1..10).each { |id| index << {id: id, description: "hello"} }
      commit_and_reload
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

        expect(Tantiny::Query).to receive(method_name).with(index, *any_args)

        index.send(method_name, *any_args)
      end
    end
  end
end
