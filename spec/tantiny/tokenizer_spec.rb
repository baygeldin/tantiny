# frozen_string_literal: true

RSpec.describe Tantiny::Tokenizer do
  describe "::default" do
    it "creates a simple tokenizer" do
      expect(Tantiny::Tokenizer).to receive(:new).with(:simple)

      Tantiny::Tokenizer.default
    end
  end

  describe "::new" do
    it "raises error for unknown tokenizer type" do
      expect {
        Tantiny::Tokenizer.new(:whatever)
      }.to raise_error(Tantiny::UnknownTokenizer)
    end
  end

  describe ".terms" do
    subject(:result) { tokenizer.terms(text) }

    context "when simple tokenizer" do
      let(:tokenizer) { Tantiny::Tokenizer.new(:simple) }
      let(:text) { "Well, not even last night's storm could wake you." }

      it "breaks the text into simple terms" do
        expect(subject).to eq(%w[well not even last night s storm could wake you])
      end
    end

    context "when stemmer tokenizer" do
      let(:tokenizer) { Tantiny::Tokenizer.new(:stemmer, language: :ru) }
      let(:text) { "Ну ты и соня, тебя даже вчерашний шторм не разбудил!" }

      it "breaks the text into stems of specified language" do
        expect(subject).to eq(%w[ну ты и сон теб даж вчерашн шторм не разбуд])
      end
    end

    context "when ngram tokenizer" do
      let(:tokenizer) { Tantiny::Tokenizer.new(:ngram, min: 3, max: 10, prefix_only: true) }
      let(:text) { "Morrowind" }

      it "breaks the text into ngrams of specified size" do
        expect(subject).to eq(%w[Mor Morr Morro Morrow Morrowi Morrowin Morrowind])
      end
    end
  end
end
