use std::collections::HashMap;
use std::str::FromStr;
use rutie::{methods, Object, AnyObject, Integer, NilClass, Array, RString, Hash};
use tantivy::{doc, Document, Term, ReloadPolicy, Index, IndexWriter, IndexReader, DateTime};
use tantivy::schema::{Schema, TextOptions, TextFieldIndexing, IndexRecordOption, FacetOptions, STRING, STORED, INDEXED, FAST};
use tantivy::collector::TopDocs;
use tantivy::directory::MmapDirectory;

use crate::helpers::{scaffold, try_unwrap_params, TryUnwrap};
use crate::query::{unwrap_query, RTantinyQuery};
use crate::tokenizer::{unwrap_tokenizer, RTantinyTokenizer};

pub struct TantinyIndex {
    pub(crate) schema: Schema,
    pub(crate) index: Index,
    pub(crate) index_writer: Option<IndexWriter>,
    pub(crate) index_reader: IndexReader,
}

scaffold!(RTantinyIndex, TantinyIndex, "Index");

pub(crate) fn unwrap_index(index: &RTantinyIndex) -> &TantinyIndex {
    index.get_data(&*TANTINY_INDEX_WRAPPER)
}

pub(crate) fn unwrap_index_mut(index: &mut RTantinyIndex) -> &mut TantinyIndex {
    index.get_data_mut(&*TANTINY_INDEX_WRAPPER)
}

#[rustfmt::skip::macros(methods)]
methods!(
    RTantinyIndex,
    _itself,

    fn new_index(
        path: RString,
        default_tokenizer: AnyObject,
        field_tokenizers: Hash,
        text_fields: Array,
        string_fields: Array,
        integer_fields: Array,
        double_fields: Array,
        date_fields: Array,
        facet_fields: Array
    ) -> RTantinyIndex {
        try_unwrap_params!(
            path: String,
            default_tokenizer: RTantinyTokenizer,
            field_tokenizers: HashMap<String, RTantinyTokenizer>,
            text_fields: Vec<String>,
            string_fields: Vec<String>,
            integer_fields: Vec<String>,
            double_fields: Vec<String>,
            date_fields: Vec<String>,
            facet_fields: Vec<String>
        );

        let index_path = MmapDirectory::open(path).try_unwrap();
        let mut schema_builder = Schema::builder();

        schema_builder.add_text_field("id", STRING | STORED);

        for field in text_fields {
            let tokenizer_name =
                if field_tokenizers.contains_key(&field) {
                    &*field
                } else {
                    "default"
                };
            let indexing = TextFieldIndexing::default()
                .set_tokenizer(tokenizer_name)
                .set_index_option(IndexRecordOption::WithFreqsAndPositions);
            let options = TextOptions::default()
                .set_indexing_options(indexing);
            schema_builder.add_text_field(&field, options);
        }

        for field in string_fields {
            schema_builder.add_text_field(&field, STRING);
        }

        for field in integer_fields {
            schema_builder.add_i64_field(&field, FAST | INDEXED);
        }

        for field in double_fields {
            schema_builder.add_f64_field(&field, FAST | INDEXED);
        }

        for field in date_fields {
            schema_builder.add_date_field(&field, FAST | INDEXED);
        }

        for field in facet_fields {
            let options = FacetOptions::default().set_indexed();
            schema_builder.add_facet_field(&field, options);
        }

        let schema = schema_builder.build();
        let index = Index::open_or_create(index_path, schema.clone()).try_unwrap();
        let tokenizers = index.tokenizers();

        tokenizers.register("default", unwrap_tokenizer(&default_tokenizer).clone());

        for (field, tokenizer) in field_tokenizers {
            tokenizers.register(&field, unwrap_tokenizer(&tokenizer).clone())
        }

        let index_writer = None;

        let index_reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()
            .try_unwrap();
        
        klass().wrap_data(
            TantinyIndex { index, index_writer, index_reader, schema },
            &*TANTINY_INDEX_WRAPPER
        )
    }

    fn add_document(
        id: RString,
        text_fields: Hash,
        string_fields: Hash,
        integer_fields: Hash,
        double_fields: Hash,
        date_fields: Hash,
        facet_fields: Hash
    ) -> NilClass {
        try_unwrap_params!(
            id: String,
            text_fields: HashMap<String, String>,
            string_fields: HashMap<String, String>,
            integer_fields: HashMap<String, i64>,
            double_fields: HashMap<String, f64>,
            date_fields: HashMap<String, String>,
            facet_fields: HashMap<String, String>
        );

        let internal = unwrap_index(&_itself);
        let index_writer = internal.index_writer.as_ref().try_unwrap();
        let schema = &internal.schema;

        let mut doc = Document::default();

        let id_field = schema.get_field("id").try_unwrap();
        doc.add_text(id_field, &id);

        for (key, value) in text_fields.iter() {
            let field = schema.get_field(key).try_unwrap();
            doc.add_text(field, value);
        }

        for (key, value) in string_fields.iter() {
            let field = schema.get_field(key).try_unwrap();
            doc.add_text(field, value);
        }

        for (key, &value) in integer_fields.iter() {
            let field = schema.get_field(key).try_unwrap();
            doc.add_i64(field, value);
        }

        for (key, &value) in double_fields.iter() {
            let field = schema.get_field(key).try_unwrap();
            doc.add_f64(field, value);
        }

        for (key, value) in date_fields.iter() {
            let field = schema.get_field(key).try_unwrap();
            let value = DateTime::from_str(value).try_unwrap();
            doc.add_date(field, &value);
        }

        for (key, value) in facet_fields.iter() {
            let field = schema.get_field(key).try_unwrap();
            doc.add_facet(field, &value);
        }

        let doc_id = Term::from_field_text(id_field, &id);
        index_writer.delete_term(doc_id.clone());

        index_writer.add_document(doc);

        NilClass::new()
    }

    fn delete_document(id: RString) -> NilClass {
        try_unwrap_params!(id: String);

        let internal = unwrap_index(&_itself);
        let index_writer = internal.index_writer.as_ref().unwrap();

        let id_field = internal.schema.get_field("id").try_unwrap();
        let doc_id = Term::from_field_text(id_field, &id);

        index_writer.delete_term(doc_id.clone());

        NilClass::new()
    }

    fn acquire_index_writer(
        overall_memory: Integer
    ) -> NilClass {
        try_unwrap_params!(overall_memory: i64);

        let internal = unwrap_index_mut(&mut _itself);

        let mut index_writer = internal.index
            .writer(overall_memory as usize)
            .try_unwrap();

        internal.index_writer = Some(index_writer);

        NilClass::new()
    }

    fn release_index_writer() -> NilClass {
        let internal = unwrap_index_mut(&mut _itself);

        let _ = internal.index_writer.as_ref().try_unwrap();
        internal.index_writer = None;

        NilClass::new()
    }

    fn commit() -> NilClass {
        let internal = unwrap_index_mut(&mut _itself);
        let index_writer = internal.index_writer.as_mut().try_unwrap();

        index_writer.commit().try_unwrap();

        NilClass::new()
    }

    fn reload() -> NilClass {
        unwrap_index(&_itself).index_reader.reload().try_unwrap();

        NilClass::new()
    }

    fn search(
        query: AnyObject,
        limit: Integer
    ) -> Array {
        try_unwrap_params!(
            query: RTantinyQuery,
            limit: i64
        );

        let internal = unwrap_index(&_itself);
        let id_field = internal.schema.get_field("id").try_unwrap();
        let searcher = internal.index_reader.searcher();
        let query = unwrap_query(&query);

        let top_docs = searcher
            .search(query, &TopDocs::with_limit(limit as usize))
            .try_unwrap();

        let mut array = Array::with_capacity(top_docs.len());

        for (_score, doc_address) in top_docs {
            let doc = searcher.doc(doc_address).try_unwrap();
            if let Some(value) = doc.get_first(id_field) {
                if let Some(id) = (&*value).text() {
                    array.push(RString::from(String::from(id)));
                }
            }
        }

        array
    }
);

pub(super) fn init() {
    klass().define(|klass| {
        klass.def_self("__new", new_index);
        klass.def("__add_document", add_document);
        klass.def("__delete_document", delete_document);
        klass.def("__acquire_index_writer", acquire_index_writer);
        klass.def("__release_index_writer", release_index_writer);
        klass.def("__commit", commit);
        klass.def("__reload", reload);
        klass.def("__search", search);
    });
} 