# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "thermite/tasks"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new
Thermite::Tasks.new

desc "Run Ruby Next nextify"
task :nextify do
  sh "bundle exec ruby-next nextify ./lib -V"
end

task build: "thermite:build"
task clean: "thermite:clean"

desc "Run Steep static types check"
task :steep do
  require "steep"
  require "steep/cli"

  Steep::CLI.new(argv: ["check"], stdout: $stdout, stderr: $stderr, stdin: $stdin).run
end

namespace :steep do
  desc "Run Steep static types stats"
  task :stats do
    exec "bundle exec steep stats"
  end
end

task default: %i[steep spec rubocop]
