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

module Tantiny
  Rutie.new(:tantiny, lib_path: __dir__, lib_prefix: "").init("Init_tantiny", __dir__)
end
