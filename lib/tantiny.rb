# frozen_string_literal: true

require "ruby-next/language/setup"
RubyNext::Language.setup_gem_load_path

require "rutie"
require "thermite/fiddle"
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
  project_dir = File.expand_path("../..", __FILE__)

  Thermite::Fiddle.load_module(
    "Init_tantiny",
    cargo_project_path: project_dir,
    ruby_project_path: project_dir
  )
end
