# frozen_string_literal: true

require "ruby-next/language/setup"
RubyNext::Language.setup_gem_load_path

require "rutie"
require "concurrent"
require "fileutils"

require "tantiny/version"
require "tantiny/errors"
require "tantiny/helpers"
require "tantiny/schema"
require "tantiny/tokenizer"
require "tantiny/query"
require "tantiny/index"

require_relative "tantiny.so"

module Tantiny
end
