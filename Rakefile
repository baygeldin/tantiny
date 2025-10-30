# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "thermite/tasks"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new
Thermite::Tasks.new

task build: "thermite:build"
task clean: "thermite:clean"

task default: %i[spec rubocop]
