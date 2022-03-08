[![Build workflow](https://github.com/baygeldin/tantiny/actions/workflows/build.yml/badge.svg)](https://github.com/baygeldin/tantiny/actions/workflows/build.yml)
[![Tantiny](https://img.shields.io/gem/v/tantiny?color=31c553)](https://rubygems.org/gems/tantiny)
[![Maintainability](https://api.codeclimate.com/v1/badges/1b466b52d2ba71ab9d80/maintainability)](https://codeclimate.com/github/baygeldin/tantiny/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/1b466b52d2ba71ab9d80/test_coverage)](https://codeclimate.com/github/baygeldin/tantiny/test_coverage)

# Tantiny

Need a fast full-text search for your Ruby script, but Solr and Elasticsearch are an overkill? 😏

You're in the right place. **Tantiny** is a minimalistic full-text search library for Ruby based on [Tantivy](https://github.com/quickwit-oss/tantivy) (an awesome alternative to Apache Lucene written in Rust). It's great for cases when your task at hand requires a full-text search, but configuring a full-blown distributed search engine would take more time than the task itself. And even if you already use such an engine in your project (which is highly likely, actually), it still might be easier to just use Tantiny instead because unlike Solr and Elasticsearch it doesn't need *anything* to work (no separate server or process or whatever), it's purely embeddable. So, when you find yourself in a situation when using your search engine of choice would be tricky/inconvinient or would require additional setup you can always revert back to a quick and dirty solution that is nontheless flexible and fast.

Tantiny is not exactly bindings to Tantivy, but it tries to be close. The main philosophy is to provide low-level access to Tantivy's inverted index, but with a nice Ruby-esque API, sensible defaults, and additional functionality sprinkled on top.

Take a look at the most basic example:

```ruby
index = Tantiny::Index.new("/path/to/index") { text :description }

index << { id: 1, description: "Hello World!" }
index << { id: 2, description: "What's up?" }
index << { id: 3, description: "Goodbye World!" }

index.commit
index.reload

index.search("world") # 1, 3
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tantiny'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install tantiny

You don't **have to** have Rust installed on your system since Tantiny will try to download the pre-compiled binaries hosted on GitHub releases during the installation. However, if no pre-compiled binaries were found for your system (which is a combination of platform, architecture, and Ruby version) you will need to [install Rust](https://www.rust-lang.org/tools/install) first.

## Defining the index

You have to specify a path to where the index would be stored and a block that defines the schema:

```ruby
Tantiny::Index.new "/tmp/index" do
  id :imdb_id
  facet :category
  string :title
  text :description
  integer :duration
  double :rating
  date :release_date
end
```

Here are the descriptions for every field type:

| Type | Description |
| --- | --- |
| id | Specifies where documents' ids are stored (defaults to `:id`). |
| facet | Fields with values like `/animals/birds` (i.e. hierarchial categories). |
| string | Fields with text that are **not** tokenized. |
| text | Fields with text that are tokenized by the specified tokenizer. |
| integer | Fields with integer values. |
| double  | Fields with float values. |
| date | Fields with either `DateTime` type or something that converts to it. |

## Managing documents

You can feed the index any kind of object that has methods specified in your schema, but plain hashes also work:

```ruby
rio_bravo = OpenStruct.new(
  imdb_id: "tt0053221",
  type: '/western/US',
  title: "Rio Bravo",
  description: "A small-town sheriff enlists a drunk, a kid and an old man to help him fight off a ruthless cattle baron.",
  duration: 141,
  rating: 8.0,
  release_date: Date.parse("March 18, 1959")
)

hanabi = {
  imdb_id: "tt0119250",
  type: "/crime/Japan",
  title: "Hana-bi",
  description: "Nishi leaves the police in the face of harrowing personal and professional difficulties. Spiraling into depression, he makes questionable decisions.",
  duration: 103,
  rating: 7.7,
  release_date: Date.parse("December 1, 1998")
}

brother = {
  imdb_id: "tt0118767",
  type: "/crime/Russia",
  title: "Brother",
  description: "An ex-soldier with a personal honor code enters the family crime business in St. Petersburg, Russia.",
  duration: 99,
  rating: 7.9,
  release_date: Date.parse("December 12, 1997")
}

index << rio_bravo
index << hanabi
index << brother
```

In order to update the document just add it again (as long as the id is the same):

```ruby
rio_bravo.rating = 10.0
index << rio_bravo
```

You can also delete it if you want:

```ruby
index.delete(rio_bravo.imdb_id)
```

After that you need to commit the index for the changes to take place:

```ruby
index.commit
```

## Searching

Make sure that your index is up-to-date by reloading it first:

```ruby
index.reload
```

And search it (finally!):

```ruby
index.search("a drunk, a kid, and an old man")
```

By default it will return ids of 10 best matching documents, but you can customize it:

```ruby
index.search("a drunk, a kid, and an old man", limit: 100)
```

You may wonder, how exactly does it conduct the search? Well, the default behavior is to use `smart_query` search (see below for details) over all `text` fields defined in your schema. So, you can pass the parameters that the `smart_query` accepts right here:

```ruby
index.search("a dlunk, a kib, and an olt mab", fuzzy_distance: 1)
```

However, you can customize it by composing your own query out of basic building blocks: 

```ruby
popular_movies = index.range_query(:rating, 8.0..10.0)
about_sheriffs = index.term_query(:description, "sheriff")
crime_movies = index.facet_query(:cetegory, "/crime")
long_ass_movies = index.range_query(:duration, 180..9999)
something_flashy = index.smart_query(:description, "bourgeoisie")

index.search((popular_movies & about_sheriffs) | (crime_movies & !long_ass_movies) | something_flashy)
```

I know, weird taste! But pretty cool, huh? Take a look at all the available queries below.

### Supported queries

| Query | Behavior |
| --- | --- |
| all_query | Returns all indexed documents. |
| empty_query | Returns exactly nothing (used internally). |
| term_query | Documents that contain the specified term. |
| fuzzy_term_query | Documents that contain the specified term within a Levenshtein distance. |
| phrase_query | Documents that contain the specified sequence of terms. |
| regex_query | Documents that contain a term that matches the specified regex. |
| prefix_query | Documents that contain a term with the specified prefix. |
| range_query | Documents that with an `integer`, `double` or `date` field within the specified range. |
| facet_query | Documents that belong to the specified category. |
| smart_query | A combination of `term_query`, `fuzzy_term_query` and `prefix_query`. |

Take a look at the [signatures file](https://github.com/baygeldin/tantiny/blob/main/sig/tantiny/query.rbs) to see what parameters do queries accept.

### Searching on multiple fields

All queries can search on multuple fields (except for `facet_query` because it doesn't make sense there).

So, the following query:

```ruby
index.term_query(%i[title, description], "hello")
```

Is equivalent to:

```ruby
index.term_query(:title, "hello") | index.term_query(:description, "hello")
```

### Boosting queries

All queries support the `boost` parameter that allows to bump documents position in the search:

```ruby
about_cowboys = index.term_query(:description, "cowboy", boost: 2.0)
about_samurai = index.term_query(:description, "samurai") # sorry, Musashi...

index.search(about_cowboys | about_samurai)
```

### `smart_query` behavior

The `smart_query` search will extract terms from your query string using the respective field tokenizers and search the index for documents that contain those terms via the `term_query`. If the `fuzzy_distance` parameter is specified it will use the `fuzzy_term_query`. Also, it allows the last term to be unfinished by using the `prefix_query`.

So, the following query:

```ruby
index.smart_query(%i[en_text ru_text], "dollars рубли eur", fuzzy_distance: 1)
```

Is equivalent to:

```ruby
t1_en = index.fuzzy_term_query(:en_text, "dollar")
t2_en = index.fuzzy_term_query(:en_text, "рубли")
t3_en = index.fuzzy_term_query(:en_text, "eur")
t3_prefix_en = index.prefix_query(:en_text, "eur")

t1_ru = index.fuzzy_term_query(:ru_text, "dollars")
t2_ru = index.fuzzy_term_query(:ru_text, "рубл")
t3_ru = index.fuzzy_term_query(:ru_text, "eur")
t3_prefix_ru = index.prefix_query(:ru_text, "eur")

(t1_en & t2_en & (t3_en | t3_prefix_en)) | (t1_ru & t2_ru & (t3_ru | t3_prefix_ru))
```

Notice how words "dollars" and "рубли" are stemmed differently depending on the field we are searching. This is assuming we have `en_text` and `ru_text` fields in our schema that use English and Russian stemmer tokenizers respectively.

### About `regex_query`

The `regex_query` accepts the regex pattern, but it has to be a [Rust regex](https://docs.rs/regex/latest/regex/#syntax), not a Ruby `Regexp`. So, instead of `index.regex_query(:description, /hel[lp]/)` you need to use `index.regex_query(:description, "hel[lp]")`. As a side note, the `regex_query` is pretty fast because it uses the [fst crate](https://github.com/BurntSushi/fst) internally.

## Tokenizers

So, we've mentioned tokenizers more than once already. What are they?

Tokenizers is what Tantivy uses to chop your text onto terms to build an inverted index. Then you can search the index by these terms. It's an important concept to understand so that you don't get confused when `index.term_query(:description, "Hello")` returns nothing because `Hello` isn't a term, but `hello` is. You have to extract the terms from the query before searching the index. Currently, only `smart_query` does that for you. Also, the only field type that is tokenized is `text`, so for `string` fields you should use the exact match (i.e. `index.term_query(:title, "Hello")`). 

### Specifying the tokenizer

By default the `simple` tokenizer is used, but you can specify the desired tokenizer globally via index options or locally via field specific options:

```ruby
en_stemmer = Tantiny::Tokenizer.new(:stemmer)
ru_stemmer = Tantiny::Tokenizer.new(:stemmer, language: :ru)

Tantiny::Index.new "/tmp/index", tokenizer: en_stemmer do
  text :description_en
  text :description_ru, tokenizer: ru_stemmer
end
```

### Simple tokenizer

Simple tokenizer chops the text on punctuation and whitespaces, removes long tokens, and lowercases the text.

```ruby
tokenizer = Tantiny::Tokenizer.new(:simple)
tokenizer.terms("Hello World!") # ["hello", "world"]
```

### Stemmer tokenizer

Stemmer tokenizers is exactly like simple tokenizer, but with additional stemming according to the specified language (defaults to English).

```ruby
tokenizer = Tantiny::Tokenizer.new(:stemmer, language: :ru)
tokenizer.terms("Привет миру сему!") # ["привет", "мир", "сем"]
```

Take a look at the [source](https://github.com/baygeldin/tantiny/blob/main/src/helpers.rs) to see what languages are supported.

### Ngram tokenizer

Ngram tokenizer chops your text onto ngrams of specified size.

```ruby
tokenizer = Tantiny::Tokenizer.new(:ngram, min: 5, max: 10, prefix_only: true)
tokenizer.terms("Morrowind") # ["Morro", "Morrow", "Morrowi", "Morrowin", "Morrowind"]
```
## Retrieving documents

You may have noticed that `search` method returns only documents ids. This is by design. The documents themselves are **not** stored in the index. Tantiny is a minimalistic library, so it tries to keep things simple. If you need to retrieve a full document, use a key-value store like Redis alongside.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

We use [conventional commits](https://www.conventionalcommits.org) to automatically generate the CHANGELOG, bump the semantic version, and to publish and release the gem. All you need to do is stick to the convention and [CI will take care of everything else](https://github.com/baygeldin/tantiny/blob/main/.github/workflows/release.yml) for you.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/baygeldin/tantiny.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
