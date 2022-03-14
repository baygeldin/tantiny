# frozen_string_literal: true

module Tantiny
  module Helpers
    def self.timestamp(date)
      date.to_datetime.iso8601
    end

    def self.with_lock(lockfile)
      File.open(lockfile, File::CREAT) do |file|
        file.flock(File::LOCK_EX)

        yield

        file.flock(File::LOCK_UN)
      end
    end
  end
end
