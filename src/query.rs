use std::str::FromStr;
use std::ops::Bound::Included;
use rutie::{methods, Object, AnyObject, Integer, Float, Array, RString};
use tantivy::{Term, DateTime};
use tantivy::schema::{IndexRecordOption, Facet, Type, FieldType};
use tantivy::query::*;

use crate::helpers::{try_unwrap_params, scaffold, TryUnwrap};
use crate::index::{unwrap_index, RTantinyIndex};

pub struct TantinyQuery(pub(crate) Box<dyn Query>);

scaffold!(RTantinyQuery, TantinyQuery, "Query");

fn wrap_query(query: Box<dyn Query>) -> RTantinyQuery {
    klass().wrap_data(
        TantinyQuery(query),
        &*TANTINY_QUERY_WRAPPER
    )
}

pub(crate) fn unwrap_query(query: &RTantinyQuery) -> &Box<dyn Query> {
    &query.get_data(&*TANTINY_QUERY_WRAPPER).0
}

#[rustfmt::skip::macros(methods)]
methods!(
    RTantinyQuery,
    _itself,

    fn new_all_query() -> RTantinyQuery {
        wrap_query(Box::new(AllQuery))
    }

    fn new_empty_query() -> RTantinyQuery {
        wrap_query(Box::new(EmptyQuery))
    }

    fn new_term_query(
        index: RTantinyIndex,
        field: RString,
        term: RString
    ) -> RTantinyQuery {
        try_unwrap_params!(
            index,
            field: String,
            term: String
        );

        let schema = &unwrap_index(&index).schema;
        let field = schema.get_field(&field).try_unwrap();
        let term = Term::from_field_text(field, &term);
        let query = TermQuery::new(term, IndexRecordOption::Basic);

        wrap_query(Box::new(query))
    }

    fn new_fuzzy_term_query(
        index: RTantinyIndex,
        field: RString,
        term: RString,
        distance: Integer
    ) -> RTantinyQuery {
        try_unwrap_params!(
            index,
            field: String,
            term: String,
            distance: i64
        );

        let schema = &unwrap_index(&index).schema;
        let field = schema.get_field(&field).try_unwrap();
        let term = Term::from_field_text(field, &term);
        let query = FuzzyTermQuery::new(term, distance as u8, true);

        wrap_query(Box::new(query))
    }

    fn new_phrase_query(
        index: RTantinyIndex,
        field: RString,
        terms: Array
    ) -> RTantinyQuery {
        try_unwrap_params!(
            index,
            field: String,
            terms: Vec<String>
        );

        let schema = &unwrap_index(&index).schema;
        let field = schema.get_field(&field).try_unwrap();

        let terms: Vec<Term> = terms.into_iter().map(|term| {
            Term::from_field_text(field, &term)
        }).collect();
        let query = PhraseQuery::new(terms);

        wrap_query(Box::new(query))
    }

    fn new_regex_query(
        index: RTantinyIndex,
        field: RString,
        regex: RString
    ) -> RTantinyQuery {
        try_unwrap_params!(
            index,
            field: String,
            regex: String
        );

        let schema = &unwrap_index(&index).schema;
        let field = schema.get_field(&field).try_unwrap();
        let query = RegexQuery::from_pattern(&regex, field).try_unwrap();

        wrap_query(Box::new(query))
    }

    fn new_range_query(
        index: RTantinyIndex,
        field: RString,
        from: AnyObject,
        to: AnyObject
    ) -> RTantinyQuery {
        try_unwrap_params!(index, from, to, field: String);

        let schema = &unwrap_index(&index).schema;
        let field = schema.get_field(&field).try_unwrap();
        let field_name = schema.get_field_name(field);
        let field_type = schema.get_field_entry(field).field_type();

        let range = match field_type {
            FieldType::Date(_) => {
                let from: String = from.try_unwrap();
                let to: String = to.try_unwrap();
                let from = DateTime::from_str(&from).try_unwrap();
                let to = DateTime::from_str(&to).try_unwrap();

                Ok((
                    Type::Date,
                    Included(Term::from_field_date(field, &from)),
                    Included(Term::from_field_date(field, &to))
                ))
            },
            FieldType::I64(_) => {
                let from: i64 = from.try_unwrap();
                let to: i64 = to.try_unwrap();

                Ok((
                    Type::I64,
                    Included(Term::from_field_i64(field, from)),
                    Included(Term::from_field_i64(field, to))
                ))
            },
            FieldType::F64(_) => {
                let from: f64 = from.try_unwrap();
                let to: f64 = to.try_unwrap();

                Ok((
                    Type::F64,
                    Included(Term::from_field_f64(field, from)),
                    Included(Term::from_field_f64(field, to))
                ))
            },
            _ => { Err(format!("Field '{}' is not supported by range query.", field_name)) }
        };

        let (value_type, left, right) = range.try_unwrap();

        let query = RangeQuery::new_term_bounds(field, value_type, &left, &right);

        wrap_query(Box::new(query))
    }

    fn new_facet_query(
        index: RTantinyIndex,
        field: RString,
        path: RString
    ) -> RTantinyQuery {
        try_unwrap_params!(
            index,
            field: String,
            path: String
        );

        let schema = &unwrap_index(&index).schema;
        let field = schema.get_field(&field).try_unwrap();
        let facet = Facet::from(&path);
        let term = Term::from_facet(field, &facet);
        let query = TermQuery::new(term, IndexRecordOption::Basic);

        wrap_query(Box::new(query))
    }

    fn disjunction(queries: Array) -> RTantinyQuery {
        try_unwrap_params!(queries);

        let mut query_vec = Vec::new();

        for query in queries {
            let query: RTantinyQuery = query.try_unwrap();
            query_vec.push((Occur::Should, unwrap_query(&query).box_clone()));
        }

        let disjunction_query = BooleanQuery::from(query_vec);

        wrap_query(Box::new(disjunction_query))
    }

    fn conjunction(queries: Array) -> RTantinyQuery {
        try_unwrap_params!(queries);

        let mut query_vec = Vec::new();

        for query in queries {
            let query: RTantinyQuery = query.try_unwrap();
            query_vec.push((Occur::Must, unwrap_query(&query).box_clone()));
        }

        let conjunction_query = BooleanQuery::from(query_vec);

        wrap_query(Box::new(conjunction_query))
    }

    fn negation() -> RTantinyQuery {
        // See: https://github.com/quickwit-oss/tantivy/issues/1153
        let all_query: Box<dyn Query> = Box::new(AllQuery);
        let negation_query = BooleanQuery::from(vec![
            (Occur::Must, all_query.box_clone()),
            (Occur::MustNot, unwrap_query(&_itself).box_clone()),
        ]);

        wrap_query(Box::new(negation_query))
    }

    fn boost(score: Float) -> RTantinyQuery {
        try_unwrap_params!(score: f64);

        let query = BoostQuery::new(unwrap_query(&_itself).box_clone(), score as f32);

        wrap_query(Box::new(query))
    }
);

pub(super) fn init() {
    klass().define(|klass| {
        klass.def_self("__new_all_query", new_all_query);
        klass.def_self("__new_empty_query", new_empty_query);
        klass.def_self("__new_term_query", new_term_query);
        klass.def_self("__new_fuzzy_term_query", new_fuzzy_term_query);
        klass.def_self("__new_regex_query", new_regex_query);
        klass.def_self("__new_range_query", new_range_query);
        klass.def_self("__new_phrase_query", new_phrase_query);
        klass.def_self("__new_facet_query", new_facet_query);
        klass.def_self("__disjunction", disjunction);
        klass.def_self("__conjunction", conjunction);
        klass.def("__negation", negation);
        klass.def("__boost", boost);
    });
} 