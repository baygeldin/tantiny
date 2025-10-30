#!/usr/bin/env ruby
# frozen_string_literal: true

# Add lib directory to load path to use the local tantiny gem
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "tantiny"

# Create an in-memory index with schema for product search
# We define separate fields for title and description to enable custom ranking
puts "Creating in-memory ecommerce index..."
index = Tantiny::Index.new do
  id :product_id
  text :title
  text :description
  string :category
  double :price
  integer :stock
end

# Sample product data
products = [
  {
    product_id: "laptop-001",
    title: "UltraBook Pro Laptop",
    description: "High-performance laptop with 16GB RAM and SSD storage. Perfect for professionals and gamers.",
    category: "Electronics",
    price: 1299.99,
    stock: 15
  },
  {
    product_id: "laptop-002",
    title: "Gaming Laptop Elite",
    description: "Premium gaming machine with RTX graphics card and RGB keyboard.",
    category: "Electronics",
    price: 1899.99,
    stock: 8
  },
  {
    product_id: "laptop-003",
    title: "Budget Notebook",
    description: "Affordable laptop for everyday tasks and web browsing. Great value for money.",
    category: "Electronics",
    price: 499.99,
    stock: 30
  },
  {
    product_id: "desk-001",
    title: "Standing Desk Pro",
    description: "Adjustable standing desk for better posture. Includes laptop stand and cable management.",
    category: "Furniture",
    price: 599.99,
    stock: 12
  },
  {
    product_id: "mouse-001",
    title: "Wireless Mouse",
    description: "Ergonomic wireless mouse compatible with laptops and desktops. Long battery life.",
    category: "Accessories",
    price: 29.99,
    stock: 100
  }
]

# Index all products
puts "\nIndexing #{products.length} products..."
index.transaction do
  products.each do |product|
    index << product
    puts "  ✓ Indexed: #{product[:title]}"
  end
end

# Reload the index to make documents searchable
index.reload
puts "\n" + "=" * 80

# Example 1: Basic search
puts "\n📍 EXAMPLE 1: Basic Search for 'laptop'"
puts "-" * 80
query = index.smart_query(:title, "laptop")
results = index.search(query, limit: 10)
puts "Found #{results.length} results:"
results.each_with_index do |product_id, i|
  product = products.find { |p| p[:product_id] == product_id }
  puts "  #{i + 1}. #{product[:title]} - $#{product[:price]}"
end

# Example 2: Fuzzy search (handling typos)
puts "\n📍 EXAMPLE 2: Fuzzy Search for 'loptop' (typo)"
puts "-" * 80
puts "Using fuzzy_distance: 1 to handle typos..."
fuzzy_query = index.smart_query(:title, "loptop", fuzzy_distance: 1)
results = index.search(fuzzy_query, limit: 10)
puts "Found #{results.length} results despite the typo:"
results.each_with_index do |product_id, i|
  product = products.find { |p| p[:product_id] == product_id }
  puts "  #{i + 1}. #{product[:title]} - $#{product[:price]}"
end

# Example 3: Search across multiple fields with equal weight
puts "\n📍 EXAMPLE 3: Search for 'laptop' in both title and description (equal weight)"
puts "-" * 80
query_both = index.smart_query(%i[title description], "laptop")
results = index.search(query_both, limit: 10)
puts "Found #{results.length} results:"
results.each_with_index do |product_id, i|
  product = products.find { |p| p[:product_id] == product_id }
  puts "  #{i + 1}. #{product[:title]} - $#{product[:price]}"
end

# Example 4: Ranking - title matches ranked higher than description matches
puts "\n📍 EXAMPLE 4: Ranking - Title matches before description matches"
puts "-" * 80
puts "Using boost: 3.0 for title matches..."

# Create separate queries with different boost values
title_query = index.smart_query(:title, "laptop", boost: 3.0)
description_query = index.smart_query(:description, "laptop", boost: 1.0)
ranked_query = title_query | description_query

results = index.search(ranked_query, limit: 10)
puts "Found #{results.length} results (title matches should rank higher):"
results.each_with_index do |product_id, i|
  product = products.find { |p| p[:product_id] == product_id }
  has_title_match = product[:title].downcase.include?("laptop")
  has_desc_match = product[:description].downcase.include?("laptop")
  match_info = []
  match_info << "📌 TITLE" if has_title_match
  match_info << "description" if has_desc_match
  puts "  #{i + 1}. #{product[:title]} - $#{product[:price]}"
  puts "     Matches in: #{match_info.join(", ")}"
end

# Example 5: Complex query - gaming laptops under $2000
puts "\n📍 EXAMPLE 5: Complex Query - Gaming products under $2000"
puts "-" * 80
gaming_query = index.smart_query(%i[title description], "gaming")
price_query = index.range_query(:price, 0.0..2000.0)
complex_query = gaming_query & price_query

results = index.search(complex_query, limit: 10)
puts "Found #{results.length} results:"
results.each_with_index do |product_id, i|
  product = products.find { |p| p[:product_id] == product_id }
  puts "  #{i + 1}. #{product[:title]} - $#{product[:price]}"
  puts "     #{product[:description][0..80]}..."
end

# Example 6: Fuzzy search with ranking
puts "\n📍 EXAMPLE 6: Fuzzy Search + Ranking (search for 'loptap' with typo)"
puts "-" * 80
puts "Using fuzzy_distance: 2 and title boost: 3.0..."

# Create fuzzy queries for both fields with ranking
fuzzy_title = index.smart_query(:title, "loptap", fuzzy_distance: 2, boost: 3.0)
fuzzy_desc = index.smart_query(:description, "loptap", fuzzy_distance: 2, boost: 1.0)
fuzzy_ranked_query = fuzzy_title | fuzzy_desc

results = index.search(fuzzy_ranked_query, limit: 10)
puts "Found #{results.length} results (despite 2 typos!):"
results.each_with_index do |product_id, i|
  product = products.find { |p| p[:product_id] == product_id }
  puts "  #{i + 1}. #{product[:title]} - $#{product[:price]}"
end

# Example 7: Category filtering
puts "\n📍 EXAMPLE 7: Category Search - Electronics"
puts "-" * 80
electronics_query = index.term_query(:category, "Electronics")
results = index.search(electronics_query, limit: 10)
puts "Found #{results.length} electronics products:"
results.each_with_index do |product_id, i|
  product = products.find { |p| p[:product_id] == product_id }
  puts "  #{i + 1}. #{product[:title]} - $#{product[:price]} (#{product[:category]})"
end

puts "\n" + "=" * 80
puts "\n✅ Example completed successfully!"
puts "\nKey takeaways:"
puts "  • Use boost parameter to rank title matches higher than description matches"
puts "  • Fuzzy search helps handle typos and misspellings"
puts "  • Combine queries with & (AND) and | (OR) operators"
puts "  • In-memory indexes are perfect for small to medium datasets"
puts "  • Use transactions for bulk indexing operations"
