# frozen_string_literal: true

RSpec.describe Tantiny::Helpers do
  describe "::timestamp" do
    it "returns datetime in iso8601 format" do
      expect(subject.timestamp(Date.new(2022))).to eq("2022-01-01T00:00:00+00:00")
    end
  end
end
