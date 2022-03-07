# frozen_string_literal: true

module Tantiny
  module Helpers
    def self.timestamp(date)
      date.to_datetime.iso8601
    end
  end
end
