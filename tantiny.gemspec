# frozen_string_literal: true

require_relative "lib/tantiny/version"

Gem::Specification.new do |spec|
  spec.name = "tantiny"
  spec.version = Tantiny::VERSION
  spec.authors = ["Sylvain Utard", "Alexander Baygeldin"]
  spec.homepage = "https://github.com/altertable-ai/tantiny"
  spec.summary = "Tiny full-text search for Ruby powered by Tantivy."

  spec.license = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/altertable-ai/tantiny/issues",
    "changelog_uri" => "https://github.com/altertable-ai/tantiny/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://github.com/altertable-ai/tantiny/blob/master/README.md",
    "homepage_uri" => "https://github.com/altertable-ai/tantiny",
    "source_code_uri" => "https://github.com/altertable-ai/tantiny"
  }

  spec.required_ruby_version = ">= 3.2"

  spec.files = [
    Dir.glob("bin/**/*"),
    Dir.glob("ext/**/*"),
    Dir.glob("lib/**/*"),
    Dir.glob("src/**/*"),
    "Cargo.toml",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ].flatten

  spec.extensions << "ext/Rakefile"

  spec.require_paths = ["lib"]

  spec.add_dependency "thermite", "~> 0"
  spec.add_dependency "rake", "~> 13.0"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "rexml"
  spec.add_dependency "fiddle"
  spec.add_dependency "ostruct"
end
