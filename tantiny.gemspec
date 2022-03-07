# frozen_string_literal: true

require_relative "lib/tantiny/version"

Gem::Specification.new do |spec|
  spec.name = "tantiny"
  spec.version = Tantiny::VERSION
  spec.authors = ["Alexander Baygeldin"]
  spec.email = ["a.baygeldin@gmail.com"]
  spec.homepage = "https://github.com/baygeldin/tantiny"
  spec.summary = "Tiny full-text search for Ruby powered by Tantivy."

  spec.license = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/baygeldin/tantiny/issues",
    "changelog_uri" => "https://github.com/baygeldin/tantiny/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://github.com/baygeldin/tantiny/blob/master/README.md",
    "homepage_uri" => "https://github.com/baygeldin/tantiny",
    "source_code_uri" => "https://github.com/baygeldin/tantiny"
  }

  spec.required_ruby_version = ">= 2.6"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:github)|appveyor)})
    end
  end + Dir.glob("lib/.rbnext/**/*")

  spec.extensions << "ext/Rakefile"

  spec.require_paths = ["lib"]

  if ENV["RELEASING_GEM"].nil? && File.directory?(File.join(__dir__, ".git"))
    spec.add_runtime_dependency "ruby-next", "~> 0.14.0"
  else
    spec.add_runtime_dependency "ruby-next-core", "~> 0.14.0"
  end

  spec.add_runtime_dependency "rutie", "~> 0.0.4"
  spec.add_runtime_dependency "thermite", "~> 0"
  spec.add_runtime_dependency "rake", "~> 13.0"
end
