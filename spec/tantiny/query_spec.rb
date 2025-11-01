# frozen_string_literal: true

RSpec.describe Tantiny::Query do
  before(:all) do
    en_stemmer = Tantiny::Tokenizer.new(:stemmer)

    @tmpdir = Dir.mktmpdir
    @index = Tantiny::Index.new(@tmpdir, exclusive_writer: true) do
      facet :facet
      string :string
      text :text
      text :en_text, tokenizer: en_stemmer
      double :double
      integer :integer
      date :date
    end
  end

  after(:all) do
    FileUtils.remove_dir(@tmpdir)
  end

  def add_documents(*docs)
    @index.transaction do
      docs.each { |d| @index << d }
    end

    @index.reload
  end

  def delete_documents(*docs)
    @index.transaction do
      docs.each { |d| @index.delete(d) }
    end
  end

  def search(query)
    @index.search(query).map(&:to_i)
  end

  shared_examples "a query" do
    it "raises error when field is unsupported" do
      expect {
        Tantiny::Query.send(query_type, @index, unsupported_field, *example_params)
      }.to raise_error(Tantiny::UnsupportedField)
    end

    it "supports boost factor" do
      query_1 = Tantiny::Query.send(query_type, @index, supported_field, *example_params)
      query_2 = Tantiny::Query.send(query_type, @index, supported_field, *boost_example_params, boost: 2.0)
      expect(search(query_1 | query_2).first).to eq(boost_example_result)
    end
  end

  describe "::all_query" do
    before(:all) { add_documents({id: 1}, {id: 2}) }

    it "matches all documents" do
      expect(search(Tantiny::Query.all_query)).to contain_exactly(1, 2)
    end
  end

  describe "::empty_query" do
    it "matches no documents" do
      expect(search(Tantiny::Query.empty_query)).to be_empty
    end
  end

  describe "::term_query" do
    before(:all) do
      add_documents(
        {id: 1, string: "hi"},
        {id: 2, text: "hi"},
        {id: 3, text: "kek"}
      )
    end

    after(:all) { delete_documents(1, 2, 3) }

    it_behaves_like "a query" do
      let(:query_type) { :term_query }
      let(:unsupported_field) { :integer }
      let(:supported_field) { :text }
      let(:example_params) { ["hi"] }
      let(:boost_example_params) { ["kek"] }
      let(:boost_example_result) { 3 }
    end

    it "matches documents with a specified term in text and string fields" do
      query = Tantiny::Query.term_query(@index, %i[string text], "hi")
      expect(search(query)).to contain_exactly(1, 2)
    end
  end

  describe "::fuzzy_term_query" do
    before(:all) do
      add_documents(
        {id: 1, string: "hello"},
        {id: 2, text: "hellp"},
        {id: 3, text: "kek"}
      )
    end

    after(:all) { delete_documents(1, 2, 3) }

    it_behaves_like "a query" do
      let(:query_type) { :fuzzy_term_query }
      let(:unsupported_field) { :integer }
      let(:supported_field) { :text }
      let(:example_params) { ["hello"] }
      let(:boost_example_params) { ["kek"] }
      let(:boost_example_result) { 3 }
    end

    it "matches documents with a specified term within a specified Levenshtein distance" do
      query = Tantiny::Query.fuzzy_term_query(@index, %i[string text], "helll", 1)
      expect(search(query)).to contain_exactly(1, 2)
    end
  end

  describe "::phrase_query" do
    before(:all) do
      add_documents(
        {id: 1, en_text: "one two three"},
        {id: 2, en_text: "three two one"}
      )
    end

    after(:all) { delete_documents(1, 2) }

    it "matches documents with a specified sequence of words" do
      query = Tantiny::Query.phrase_query(@index, :en_text, "ones two")
      expect(search(query)).to contain_exactly(1)
    end
  end

  describe "::regex_query" do
    before(:all) do
      add_documents(
        {id: 1, string: "hello"},
        {id: 2, text: "holla"},
        {id: 3, text: "help"}
      )
    end

    after(:all) { delete_documents(1, 2, 3) }

    it_behaves_like "a query" do
      let(:query_type) { :regex_query }
      let(:unsupported_field) { :integer }
      let(:supported_field) { :text }
      let(:example_params) { ["h[eo]ll[oa]"] }
      let(:boost_example_params) { ["hel[p]"] }
      let(:boost_example_result) { 3 }
    end

    it "matches documents with a term that matches a regex pattern" do
      query = Tantiny::Query.regex_query(@index, %i[string text], "h[eo]ll[oa]")
      expect(search(query)).to contain_exactly(1, 2)
    end
  end

  describe "::prefix_query" do
    before(:all) do
      add_documents(
        {id: 1, string: "hello"},
        {id: 2, text: "hell"},
        {id: 3, string: "he.*"}
      )
    end

    after(:all) { delete_documents(1, 2, 3) }

    it_behaves_like "a query" do
      let(:query_type) { :prefix_query }
      let(:unsupported_field) { :integer }
      let(:supported_field) { :string }
      let(:example_params) { ["hell"] }
      let(:boost_example_params) { ["he.*"] }
      let(:boost_example_result) { 3 }
    end

    it "matches documents with a term that starts with a prefix" do
      query = Tantiny::Query.prefix_query(@index, %i[string text], "hell")
      expect(search(query)).to contain_exactly(1, 2)
    end

    it "works for special characters" do
      query = Tantiny::Query.prefix_query(@index, %i[string text], "he.")
      expect(search(query)).to contain_exactly(3)
    end
  end

  describe "::range_query" do
    before(:all) do
      add_documents(
        {id: 1, integer: 42},
        {id: 2, integer: 100},
        {id: 3, double: 42.0},
        {id: 4, double: 100.0},
        {id: 5, date: Date.new(1995)},
        {id: 6, date: Date.new(2022)}
      )
    end

    after(:all) { delete_documents(*(1..6)) }

    it_behaves_like "a query" do
      let(:query_type) { :range_query }
      let(:unsupported_field) { :text }
      let(:supported_field) { :integer }
      let(:example_params) { [0..50] }
      let(:boost_example_params) { [90..110] }
      let(:boost_example_result) { 2 }
    end

    it "matches documents with integer value within a range" do
      query = Tantiny::Query.range_query(@index, :integer, 0..50)
      expect(search(query)).to contain_exactly(1)
    end

    it "matches documents with double value within a range" do
      query = Tantiny::Query.range_query(@index, :double, 0.0..50.0)
      expect(search(query)).to contain_exactly(3)
    end

    it "matches documents with date value within a range" do
      query = Tantiny::Query.range_query(@index, :date, Date.new(1900)..Date.new(2000))
      expect(search(query)).to contain_exactly(5)
    end

    it "raises error when range is unsupported" do
      expect {
        Tantiny::Query.range_query(@index, :integer, "a".."z")
      }.to raise_error(Tantiny::UnsupportedRange)
    end
  end

  describe "::facet_query" do
    before(:all) do
      add_documents(
        {id: 1, facet: "/animals/birds"},
        {id: 2, facet: "/animals/fish"},
        {id: 3, facet: "/humans"}
      )
    end

    after(:all) { delete_documents(1, 2, 3) }

    it_behaves_like "a query" do
      let(:query_type) { :facet_query }
      let(:unsupported_field) { :string }
      let(:supported_field) { :facet }
      let(:example_params) { ["/animals"] }
      let(:boost_example_params) { ["/humans"] }
      let(:boost_example_result) { 3 }
    end

    it "matches documents that within a specified hierarchy" do
      query = Tantiny::Query.facet_query(@index, :facet, "/animals")
      expect(search(query)).to contain_exactly(1, 2)
    end
  end

  describe "::smart_query" do
    before(:all) do
      add_documents(
        {id: 1, text: "one two three"},
        {id: 2, en_text: "one two three"},
        {id: 3, text: "ready steady go"}
      )
    end

    after(:all) { delete_documents(1, 2, 3) }

    def search(query, **)
      if query.is_a?(String)
        fields = @index.schema.text_fields
        query = Tantiny::Query.smart_query(@index, fields, query, **)
      end

      @index.search(query).map(&:to_i)
    end

    it_behaves_like "a query" do
      let(:query_type) { :smart_query }
      let(:unsupported_field) { :integer }
      let(:supported_field) { :text }
      let(:example_params) { ["one two"] }
      let(:boost_example_params) { ["ready steady"] }
      let(:boost_example_result) { 3 }
    end

    it "searches by multiple terms" do
      expect(search("one three")).to contain_exactly(1, 2)
    end

    it "uses field specific tokenizers" do
      expect(search("ones two threes")).to contain_exactly(2)
    end

    it "doesn't care about the order of words" do
      expect(search("three two one")).to contain_exactly(1, 2)
    end

    it "allows only last term to be unfinished" do
      expect(search("one two thr")).to contain_exactly(1, 2)
      expect(search("one tw three")).to be_empty
    end

    it "supports fuzzy search" do
      expect(search("reaby steaby bo", fuzzy_distance: 1)).to contain_exactly(3)
    end

    it "works for empty query" do
      expect(search("")).to be_empty
    end
  end

  describe "bitwise operators" do
    before(:all) do
      add_documents(
        {id: 1, text: "hello world"},
        {id: 2, text: "hello world war"},
        {id: 3, text: "world war"}
      )
    end

    after(:all) { delete_documents(1, 2, 3) }

    describe ".!" do
      it "negates the query" do
        query = Tantiny::Query.term_query(@index, :text, "hello")
        expect(search(query)).to contain_exactly(1, 2)
        expect(search(!query)).to contain_exactly(3)
      end
    end

    describe ".&" do
      it "works like logical AND" do
        query_1 = Tantiny::Query.phrase_query(@index, :text, "hello world")
        query_2 = Tantiny::Query.phrase_query(@index, :text, "world war")

        expect(search(query_1)).to contain_exactly(1, 2)
        expect(search(query_2)).to contain_exactly(2, 3)
        expect(search(query_1 & query_2)).to contain_exactly(2)
      end
    end

    describe ".|" do
      it "works like logical OR" do
        query_1 = Tantiny::Query.phrase_query(@index, :text, "hello world")
        query_2 = Tantiny::Query.phrase_query(@index, :text, "world war")

        expect(search(query_1)).to contain_exactly(1, 2)
        expect(search(query_2)).to contain_exactly(2, 3)
        expect(search(query_1 | query_2)).to contain_exactly(1, 2, 3)
      end
    end
  end

  describe ".boost" do
    before(:all) do
      add_documents(
        {id: 1, string: "hello"},
        {id: 2, text: "hello hello"}
      )

      add_documents({id: 3, string: "world"})
    end

    after(:all) { delete_documents(1, 2) }

    it "boosts the query" do
      query_1 = Tantiny::Query.term_query(@index, %i[string text], "hello")
      query_2 = Tantiny::Query.term_query(@index, :string, "world", boost: 100)

      expect(search(query_1 | query_2).first).to eq(3)
    end
  end

  describe "::highlight" do
    it "highlights exact matches" do
      highlighted = Tantiny::Query.highlight("HELLO world. you are welcome.", "hello you")
      expect(highlighted).to eq("<b>HELLO</b> world. <b>you</b> are welcome.")
    end

    it "highlights the text with fuzzy matches" do
      highlighted = Tantiny::Query.highlight("hellow world. you are welcome.", "hello you", fuzzy_distance: 1)
      expect(highlighted).to eq("<b>hellow</b> world. <b>you</b> are welcome.")
    end
  end
end
