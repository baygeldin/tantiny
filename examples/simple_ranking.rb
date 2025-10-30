#!/usr/bin/env ruby
# frozen_string_literal: true

# Add lib directory to load path to use the local tantiny gem
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "tantiny"

# Quick demonstration of ranking with title vs description
puts "Simple Ranking Example"
puts "=" * 60

# Create in-memory index
index = Tantiny::Index.new do
  text :title
  text :description
end

# Add products - some with "laptop" in title, some in description
products = [
  {id: "1", title: "MacBook Laptop", description: "Professional notebook"},
  {id: "2", title: "Gaming PC", description: "Desktop with laptop-grade portability"},
  {id: "3", title: "Laptop Stand", description: "Ergonomic stand"},
  {id: "4", title: "Desk", description: "Perfect for your laptop setup"}
]

index.transaction { products.each { |p| index << p } }
index.reload

puts "\nSearching for 'laptop'..."
puts "\n1️⃣  WITHOUT ranking (equal weight):"
query_equal = index.smart_query(%i[title description], "laptop")
results = index.search(query_equal, limit: 10)
results.each { |id| puts "   - #{products.find { |p| p[:id] == id }[:title]}" }

puts "\n2️⃣  WITH ranking (title 3x boost):"
query_title = index.smart_query(:title, "laptop", boost: 3.0)
query_desc = index.smart_query(:description, "laptop", boost: 1.0)
query_ranked = query_title | query_desc
results = index.search(query_ranked, limit: 10)
results.each { |id| puts "   - #{products.find { |p| p[:id] == id }[:title]}" }

puts "\n✅ Notice how products with 'laptop' in the title rank higher!"
