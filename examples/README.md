# Tantiny Examples

This directory contains practical examples demonstrating how to use Tantiny for various search scenarios.

## Quick Start

For a simple demonstration of title vs description ranking:

```bash
ruby examples/simple_ranking.rb
```

For a comprehensive ecommerce example:

```bash
ruby examples/ecommerce.rb
```

## Simple Ranking Example

The `simple_ranking.rb` example provides a minimal demonstration of field-based ranking. It shows:

- **Basic indexing** - Creating a simple in-memory index
- **Field weighting** - Using boost values to rank title matches higher than description matches
- **Side-by-side comparison** - See the difference between equal weights and boosted fields

This is perfect for understanding the core concept of ranking in just a few lines of code.

## Ecommerce Example

The `ecommerce.rb` example demonstrates building an in-memory search index for an ecommerce catalog. It showcases:

- **In-memory indexing** - Perfect for small to medium datasets without needing persistent storage
- **Product search** - Indexing 5 sample products with various attributes
- **Basic search** - Simple keyword searches
- **Fuzzy search** - Handling typos and misspellings (e.g., "loptop" → "laptop")
- **Field-based ranking** - Boosting title matches to rank higher than description matches
- **Complex queries** - Combining multiple conditions with AND/OR operators
- **Category filtering** - Filtering products by exact category match
- **Price range queries** - Finding products within a specific price range

### Running the Example

```bash
cd examples
ruby ecommerce.rb
```

Or from the project root:

```bash
ruby examples/ecommerce.rb
```

### Key Features Demonstrated

#### 1. Creating an In-Memory Index

```ruby
index = Tantiny::Index.new do
  id :product_id
  text :title
  text :description
  string :category
  double :price
  integer :stock
end
```

#### 2. Fuzzy Search for Typos

```ruby
# Handles "loptop" typo and finds "laptop"
fuzzy_query = index.smart_query(:title, "loptop", fuzzy_distance: 1)
```

#### 3. Field Ranking with Boost

```ruby
# Title matches ranked 3x higher than description matches
title_query = index.smart_query(:title, "laptop", boost: 3.0)
description_query = index.smart_query(:description, "laptop", boost: 1.0)
ranked_query = title_query | description_query
```

#### 4. Complex Queries

```ruby
# Find gaming products under $2000
gaming_query = index.smart_query(%i[title description], "gaming")
price_query = index.range_query(:price, 0.0..2000.0)
complex_query = gaming_query & price_query
```

### Sample Output

The script will show 7 different search scenarios with results, demonstrating:

- Which products match
- How ranking affects result order
- How fuzzy search handles typos
- How to combine different query types

### Understanding Boost Values

The `boost` parameter is a multiplier for the relevance score:

- `boost: 1.0` - Default/normal relevance
- `boost: 2.0` - Double the relevance (2x weight)
- `boost: 3.0` - Triple the relevance (3x weight)

In the ecommerce example, we use `boost: 3.0` for title matches and `boost: 1.0` for description matches, ensuring that products with the search term in their title appear before products that only mention it in the description.
