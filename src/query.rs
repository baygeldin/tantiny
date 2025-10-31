use levenshtein_automata::{Distance, LevenshteinAutomatonBuilder};
use magnus::{Error, Module, Object, RArray, RModule, Ruby, TryConvert, Value};
use std::ops::Bound::Included;
use tantivy::query::*;
use tantivy::schema::{Facet, FieldType, IndexRecordOption};
use tantivy::Term;
use time::OffsetDateTime;

use crate::index::Index;

#[magnus::wrap(class = "Tantiny::Query", free_immediately, size)]
pub struct Query(Box<dyn tantivy::query::Query>);

impl Query {
    pub fn get_query(&self) -> &dyn tantivy::query::Query {
        self.0.as_ref()
    }

    fn new_all() -> Self {
        Query(Box::new(AllQuery))
    }

    fn new_empty() -> Self {
        Query(Box::new(EmptyQuery))
    }

    fn new_term(index: &Index, field: String, term: String) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let field = index.schema.get_field(&field).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Field not found: {}", e),
            )
        })?;
        let term = Term::from_field_text(field, &term);
        let query = TermQuery::new(term, IndexRecordOption::Basic);
        Ok(Query(Box::new(query)))
    }

    fn new_fuzzy_term(
        index: &Index,
        field: String,
        term: String,
        distance: i64,
    ) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let field = index.schema.get_field(&field).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Field not found: {}", e),
            )
        })?;
        let term = Term::from_field_text(field, &term);
        let query = FuzzyTermQuery::new(term, distance as u8, true);
        Ok(Query(Box::new(query)))
    }

    fn new_phrase(index: &Index, field: String, terms: Vec<String>) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let field = index.schema.get_field(&field).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Field not found: {}", e),
            )
        })?;

        let terms: Vec<Term> = terms
            .into_iter()
            .map(|term| Term::from_field_text(field, &term))
            .collect();
        let query = PhraseQuery::new(terms);
        Ok(Query(Box::new(query)))
    }

    fn new_regex(index: &Index, field: String, regex: String) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let field = index.schema.get_field(&field).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Field not found: {}", e),
            )
        })?;
        let query = RegexQuery::from_pattern(&regex, field).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Invalid regex: {}", e),
            )
        })?;
        Ok(Query(Box::new(query)))
    }

    fn new_range(index: &Index, field: String, from: Value, to: Value) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let field_obj = index.schema.get_field(&field).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Field not found: {}", e),
            )
        })?;
        let field_name = index.schema.get_field_name(field_obj);
        let field_type = index.schema.get_field_entry(field_obj).field_type();

        let (left, right) = match field_type {
            FieldType::Date(_) => {
                let from_str: String = String::try_convert(from)?;
                let to_str: String = String::try_convert(to)?;
                let from_datetime = OffsetDateTime::parse(
                    &from_str,
                    &time::format_description::well_known::Rfc3339,
                )
                .map_err(|e| {
                    Error::new(
                        ruby.exception_runtime_error(),
                        format!("Invalid date format: {}", e),
                    )
                })?;
                let to_datetime =
                    OffsetDateTime::parse(&to_str, &time::format_description::well_known::Rfc3339)
                        .map_err(|e| {
                            Error::new(
                                ruby.exception_runtime_error(),
                                format!("Invalid date format: {}", e),
                            )
                        })?;
                let from_dt = tantivy::DateTime::from_timestamp_nanos(
                    from_datetime.unix_timestamp_nanos() as i64,
                );
                let to_dt = tantivy::DateTime::from_timestamp_nanos(
                    to_datetime.unix_timestamp_nanos() as i64,
                );

                (
                    Term::from_field_date(field_obj, from_dt),
                    Term::from_field_date(field_obj, to_dt),
                )
            }
            FieldType::I64(_) => {
                let from_val: i64 = i64::try_convert(from)?;
                let to_val: i64 = i64::try_convert(to)?;
                (
                    Term::from_field_i64(field_obj, from_val),
                    Term::from_field_i64(field_obj, to_val),
                )
            }
            FieldType::F64(_) => {
                let from_val: f64 = f64::try_convert(from)?;
                let to_val: f64 = f64::try_convert(to)?;
                (
                    Term::from_field_f64(field_obj, from_val),
                    Term::from_field_f64(field_obj, to_val),
                )
            }
            _ => {
                return Err(Error::new(
                    ruby.exception_runtime_error(),
                    format!("Field '{}' is not supported by range query.", field_name),
                ))
            }
        };

        let query = RangeQuery::new(Included(left), Included(right));
        Ok(Query(Box::new(query)))
    }

    fn new_facet(index: &Index, field: String, path: String) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let field = index.schema.get_field(&field).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Field not found: {}", e),
            )
        })?;
        let facet = Facet::from(&path);
        let term = Term::from_facet(field, &facet);
        let query = TermQuery::new(term, IndexRecordOption::Basic);
        Ok(Query(Box::new(query)))
    }

    fn disjunction(queries: RArray) -> Result<Self, Error> {
        let mut query_vec = Vec::new();

        for item in queries.into_iter() {
            let query: &Query = <&Query>::try_convert(item)?;
            query_vec.push((Occur::Should, query.0.box_clone()));
        }

        Ok(Query(Box::new(BooleanQuery::from(query_vec))))
    }

    fn conjunction(queries: RArray) -> Result<Self, Error> {
        let mut query_vec = Vec::new();

        for item in queries.into_iter() {
            let query: &Query = <&Query>::try_convert(item)?;
            query_vec.push((Occur::Must, query.0.box_clone()));
        }

        Ok(Query(Box::new(BooleanQuery::from(query_vec))))
    }

    fn negation(&self) -> Self {
        let all_query: Box<dyn tantivy::query::Query> = Box::new(AllQuery);
        let negation_query = BooleanQuery::from(vec![
            (Occur::Must, all_query.box_clone()),
            (Occur::MustNot, self.0.box_clone()),
        ]);

        Query(Box::new(negation_query))
    }

    fn boost(&self, score: f64) -> Self {
        let query = BoostQuery::new(self.0.box_clone(), score as f32);
        Query(Box::new(query))
    }

    fn highlight(text: String, terms: Vec<String>, fuzzy_distance: i64) -> Result<String, Error> {
        use tantivy::tokenizer::{LowerCaser, SimpleTokenizer, TextAnalyzer, TokenStream};

        // Create a simple tokenizer for highlighting
        let mut analyzer = TextAnalyzer::builder(SimpleTokenizer::default())
            .filter(LowerCaser)
            .build();

        // Tokenize the input text
        let mut token_stream = analyzer.token_stream(&text);

        // Collect all tokens with their positions
        let mut tokens = Vec::new();
        while token_stream.advance() {
            let token = token_stream.token();
            tokens.push((token.text.clone(), token.offset_from, token.offset_to));
        }

        // Build Levenshtein automata for each term (same algorithm as Tantivy's FuzzyTermQuery)
        let lev_builder = LevenshteinAutomatonBuilder::new(fuzzy_distance as u8, true);
        let automata: Vec<_> = terms
            .iter()
            .map(|term| lev_builder.build_dfa(term))
            .collect();

        // Build the highlighted text
        let mut result = String::new();
        let mut last_pos = 0;

        for (token_text, start, end) in tokens {
            // Check if this token matches any of the query terms (exact or fuzzy)
            let should_highlight = terms.iter().zip(&automata).any(|(term, dfa)| {
                // Exact match
                if token_text.eq_ignore_ascii_case(term) {
                    return true;
                }

                // Fuzzy match using Levenshtein automaton (same as Tantivy's FuzzyTermQuery)
                matches!(dfa.eval(&token_text), Distance::Exact(_))
            });

            // Add the text before the token
            result.push_str(&text[last_pos..start]);

            // Add the token, highlighted if it matches
            if should_highlight {
                result.push_str("<b>");
                result.push_str(&text[start..end]);
                result.push_str("</b>");
            } else {
                result.push_str(&text[start..end]);
            }

            last_pos = end;
        }

        // Add any remaining text after the last token
        result.push_str(&text[last_pos..]);

        Ok(result)
    }
}

pub fn init(ruby: &Ruby, module: RModule) -> Result<(), Error> {
    let class = module.define_class("Query", ruby.class_object())?;

    class.define_singleton_method("__new_all_query", magnus::function!(Query::new_all, 0))?;
    class.define_singleton_method("__new_empty_query", magnus::function!(Query::new_empty, 0))?;
    class.define_singleton_method("__new_term_query", magnus::function!(Query::new_term, 3))?;
    class.define_singleton_method(
        "__new_fuzzy_term_query",
        magnus::function!(Query::new_fuzzy_term, 4),
    )?;
    class.define_singleton_method(
        "__new_phrase_query",
        magnus::function!(Query::new_phrase, 3),
    )?;
    class.define_singleton_method("__new_regex_query", magnus::function!(Query::new_regex, 3))?;
    class.define_singleton_method("__new_range_query", magnus::function!(Query::new_range, 4))?;
    class.define_singleton_method("__new_facet_query", magnus::function!(Query::new_facet, 3))?;
    class.define_singleton_method("__disjunction", magnus::function!(Query::disjunction, 1))?;
    class.define_singleton_method("__conjunction", magnus::function!(Query::conjunction, 1))?;
    class.define_method("__negation", magnus::method!(Query::negation, 0))?;
    class.define_method("__boost", magnus::method!(Query::boost, 1))?;
    class.define_singleton_method("__highlight", magnus::function!(Query::highlight, 3))?;

    Ok(())
}
