# frozen_string_literal: true

RSpec.describe Tantiny::Schema do
  subject!(:schema) do
    default_tokenizer = en_stemmer
    field_tokenizer = ru_stemmer

    Tantiny::Schema.new(default_tokenizer) do
      id :imdb_id
      facet :category
      string :title
      text :description_en
      text :description_ru, tokenizer: field_tokenizer
      integer :duration
      double :rating
      date :release_date
    end
  end

  let!(:en_stemmer) { Tantiny::Tokenizer.new(:stemmer) }
  let!(:ru_stemmer) { Tantiny::Tokenizer.new(:stemmer, language: :ru) }

  define :have_setting do |method, result|
    match { |schema| schema.send(method) == result }
  end

  it { is_expected.to have_setting(:id_field, :imdb_id) }
  it { is_expected.to have_setting(:facet_fields, %i[category]) }
  it { is_expected.to have_setting(:string_fields, %i[title]) }
  it { is_expected.to have_setting(:text_fields, %i[description_en description_ru]) }
  it { is_expected.to have_setting(:integer_fields, %i[duration]) }
  it { is_expected.to have_setting(:double_fields, %i[rating]) }
  it { is_expected.to have_setting(:date_fields, %i[release_date]) }

  describe ".tokenizer_for" do
    it "returns the specified tokenizer" do
      expect(subject.tokenizer_for(:description_ru)).to eq(ru_stemmer)
    end

    it "fallbacks to the default tokenizer" do
      expect(subject.tokenizer_for(:description_en)).to eq(en_stemmer)
    end
  end
end
