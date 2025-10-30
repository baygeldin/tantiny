# frozen_string_literal: true

require "fiddle/import"
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

  # Try multiple possible locations for the library
  lib_paths = [
    File.join(project_dir, "target", "release", "libtantiny.dylib"),
    File.join(project_dir, "target", "debug", "libtantiny.dylib"),
    File.join(project_dir, "target", "release", "libtantiny.so"),
    File.join(project_dir, "target", "debug", "libtantiny.so"),
    File.join(project_dir, "lib", "tantiny.bundle"),
    File.join(project_dir, "lib", "tantiny.so"),
    File.join(project_dir, "lib", "tantiny.dylib")
  ]

  lib_path = lib_paths.find { |path| File.exist?(path) }

  if lib_path.nil?
    raise LoadError, "Could not find tantiny library in any of: #{lib_paths.join(", ")}"
  end

  # Load the library using Fiddle and call the init function
  handle = Fiddle.dlopen(lib_path)
  Fiddle::Function.new(handle["Init_tantiny"], [], Fiddle::TYPE_VOIDP).call
end
