# frozen_string_literal: true

RSpec.describe Tantiny::Helpers do
  describe "::timestamp" do
    it "returns datetime in iso8601 format" do
      expect(subject.timestamp(Date.new(2022))).to eq("2022-01-01T00:00:00+00:00")
    end
  end

  describe "::with_lock" do
    let!(:lockfile) { Tempfile.new }

    after do
      lockfile.delete
    end

    it "creates the lockfile if it doesn't exist" do
      lockfile_path = lockfile.path
      lockfile.delete

      subject.with_lock(lockfile_path) {}

      expect(Pathname.new(lockfile_path)).to exist
    end

    it "exclusively locks the lockfile for the duration of block execution" do
      collaborator = double("Collaborator")
      file = double("File")

      allow(File).to receive(:open).and_yield(file)
      expect(file).to receive(:flock).with(File::LOCK_EX).ordered
      expect(collaborator).to receive(:hello).ordered
      expect(file).to receive(:flock).with(File::LOCK_UN).ordered

      subject.with_lock(lockfile.path) { collaborator.hello }
    end
  end
end
