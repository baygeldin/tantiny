use magnus::{r_hash::ForEach, Error, Module, Object, RHash, RModule, Ruby, TryConvert, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use tantivy::collector::TopDocs;
use tantivy::directory::MmapDirectory;
use tantivy::schema::{
    FacetOptions, IndexRecordOption, Schema, TextFieldIndexing, TextOptions, Value as TantivyValue,
    FAST, INDEXED, STORED, STRING,
};
use tantivy::{IndexReader, IndexWriter, ReloadPolicy, TantivyDocument, Term};
use time::OffsetDateTime;

use crate::helpers::hash_to_multivalue_map;
use crate::query::Query;
use crate::tokenizer::Tokenizer;

#[magnus::wrap(class = "Tantiny::Index", free_immediately, size)]
pub struct Index {
    pub schema: Schema,
    index: tantivy::Index,
    index_writer: RefCell<Option<IndexWriter>>,
    index_reader: IndexReader,
}

impl Index {
    #[allow(clippy::too_many_arguments)]
    fn new(
        path: Option<String>,
        default_tokenizer: &Tokenizer,
        field_tokenizers: RHash,
        text_fields: Vec<String>,
        string_fields: Vec<String>,
        integer_fields: Vec<String>,
        double_fields: Vec<String>,
        date_fields: Vec<String>,
        facet_fields: Vec<String>,
    ) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let field_tokenizers_map: HashMap<String, &Tokenizer> = {
            let mut map = HashMap::new();
            field_tokenizers.foreach(|key: String, value: Value| {
                let tokenizer: &Tokenizer = <&Tokenizer>::try_convert(value)?;
                map.insert(key, tokenizer);
                Ok(ForEach::Continue)
            })?;
            map
        };

        let mut schema_builder = Schema::builder();

        schema_builder.add_text_field("id", STRING | STORED);

        for field in text_fields {
            let tokenizer_name = if field_tokenizers_map.contains_key(&field) {
                &field
            } else {
                "default"
            };
            let indexing = TextFieldIndexing::default()
                .set_tokenizer(tokenizer_name)
                .set_index_option(IndexRecordOption::WithFreqsAndPositions);
            let options = TextOptions::default().set_indexing_options(indexing);
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
            schema_builder.add_facet_field(&field, FacetOptions::default());
        }

        let schema = schema_builder.build();

        // Create index based on whether path is provided
        let index = match path {
            Some(path_str) => {
                let index_path = MmapDirectory::open(path_str).map_err(|e| {
                    Error::new(
                        ruby.exception_runtime_error(),
                        format!("Failed to open directory: {}", e),
                    )
                })?;
                tantivy::Index::open_or_create(index_path, schema.clone()).map_err(|e| {
                    Error::new(
                        ruby.exception_runtime_error(),
                        format!("Failed to create index: {}", e),
                    )
                })?
            }
            None => {
                // Create in-memory index
                tantivy::Index::create_in_ram(schema.clone())
            }
        };

        // Access the tokenizers field before moving index
        let tokenizers = index.tokenizers();

        // Register tokenizers
        tokenizers.register("default", default_tokenizer.get_analyzer());

        for (field, tokenizer) in field_tokenizers_map {
            tokenizers.register(&field, tokenizer.get_analyzer())
        }

        let index_reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to create reader: {}", e),
                )
            })?;

        Ok(Index {
            schema,
            index,
            index_writer: RefCell::new(None),
            index_reader,
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn add_document(
        &self,
        id: String,
        text_fields: RHash,
        string_fields: RHash,
        integer_fields: RHash,
        double_fields: RHash,
        date_fields: RHash,
        facet_fields: RHash,
    ) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let index_writer = self.index_writer.borrow();
        let index_writer = index_writer.as_ref().ok_or_else(|| {
            Error::new(ruby.exception_runtime_error(), "No index writer available")
        })?;

        let text_map: HashMap<String, Vec<String>> = hash_to_multivalue_map(text_fields)?;
        let string_map: HashMap<String, Vec<String>> = hash_to_multivalue_map(string_fields)?;
        let integer_map: HashMap<String, Vec<i64>> = hash_to_multivalue_map(integer_fields)?;
        let double_map: HashMap<String, Vec<f64>> = hash_to_multivalue_map(double_fields)?;
        let date_map: HashMap<String, Vec<String>> = hash_to_multivalue_map(date_fields)?;
        let facet_map: HashMap<String, Vec<String>> = hash_to_multivalue_map(facet_fields)?;

        let mut doc = TantivyDocument::default();

        let id_field = self.schema.get_field("id").map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to get id field: {}", e),
            )
        })?;
        doc.add_text(id_field, &id);

        for (key, values) in text_map.iter() {
            let field = self.schema.get_field(key).map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to get field {}: {}", key, e),
                )
            })?;
            for value in values {
                doc.add_text(field, value);
            }
        }

        for (key, values) in string_map.iter() {
            let field = self.schema.get_field(key).map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to get field {}: {}", key, e),
                )
            })?;
            for value in values {
                doc.add_text(field, value);
            }
        }

        for (key, values) in integer_map.iter() {
            let field = self.schema.get_field(key).map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to get field {}: {}", key, e),
                )
            })?;
            for &value in values {
                doc.add_i64(field, value);
            }
        }

        for (key, values) in double_map.iter() {
            let field = self.schema.get_field(key).map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to get field {}: {}", key, e),
                )
            })?;
            for &value in values {
                doc.add_f64(field, value);
            }
        }

        for (key, values) in date_map.iter() {
            let field = self.schema.get_field(key).map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to get field {}: {}", key, e),
                )
            })?;
            for value in values {
                let datetime =
                    OffsetDateTime::parse(value, &time::format_description::well_known::Rfc3339)
                        .map_err(|e| {
                            Error::new(
                                ruby.exception_runtime_error(),
                                format!("Invalid date format: {}", e),
                            )
                        })?;
                doc.add_date(
                    field,
                    tantivy::DateTime::from_timestamp_nanos(datetime.unix_timestamp_nanos() as i64),
                );
            }
        }

        for (key, values) in facet_map.iter() {
            let field = self.schema.get_field(key).map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to get field {}: {}", key, e),
                )
            })?;
            for value in values {
                doc.add_facet(field, value);
            }
        }

        let doc_id = Term::from_field_text(id_field, &id);
        index_writer.delete_term(doc_id.clone());
        index_writer.add_document(doc).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to add document: {}", e),
            )
        })?;

        Ok(())
    }

    fn delete_document(&self, id: String) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let index_writer = self.index_writer.borrow();
        let index_writer = index_writer.as_ref().ok_or_else(|| {
            Error::new(ruby.exception_runtime_error(), "No index writer available")
        })?;

        let id_field = self.schema.get_field("id").map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to get id field: {}", e),
            )
        })?;
        let doc_id = Term::from_field_text(id_field, &id);

        index_writer.delete_term(doc_id.clone());
        Ok(())
    }

    fn acquire_index_writer(&self, overall_memory: i64) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let index_writer = self.index.writer(overall_memory as usize).map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to create writer: {}", e),
            )
        })?;

        *self.index_writer.borrow_mut() = Some(index_writer);
        Ok(())
    }

    fn release_index_writer(&self) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let mut writer = self.index_writer.borrow_mut();
        if writer.is_none() {
            return Err(Error::new(
                ruby.exception_runtime_error(),
                "No index writer to release",
            ));
        }
        *writer = None;
        Ok(())
    }

    fn commit(&self) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let mut writer_cell = self.index_writer.borrow_mut();
        let index_writer = writer_cell.as_mut().ok_or_else(|| {
            Error::new(ruby.exception_runtime_error(), "No index writer available")
        })?;

        index_writer.commit().map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to commit: {}", e),
            )
        })?;
        Ok(())
    }

    fn reload(&self) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        self.index_reader.reload().map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to reload: {}", e),
            )
        })?;
        Ok(())
    }

    fn search(&self, query: &Query, limit: i64) -> Result<Vec<String>, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let id_field = self.schema.get_field("id").map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to get id field: {}", e),
            )
        })?;
        let searcher = self.index_reader.searcher();

        let top_docs = searcher
            .search(query.get_query(), &TopDocs::with_limit(limit as usize))
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Search failed: {}", e),
                )
            })?;

        let mut results = Vec::with_capacity(top_docs.len());

        for (_score, doc_address) in top_docs {
            let doc: TantivyDocument = searcher.doc(doc_address).map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to get document: {}", e),
                )
            })?;
            if let Some(value) = doc.get_first(id_field) {
                if let Some(id) = value.as_str() {
                    results.push(id.to_string());
                }
            }
        }

        Ok(results)
    }
}

pub fn init(ruby: &Ruby, module: RModule) -> Result<(), Error> {
    let class = module.define_class("Index", ruby.class_object())?;

    class.define_singleton_method("__new", magnus::function!(Index::new, 9))?;
    class.define_method("__add_document", magnus::method!(Index::add_document, 7))?;
    class.define_method(
        "__delete_document",
        magnus::method!(Index::delete_document, 1),
    )?;
    class.define_method(
        "__acquire_index_writer",
        magnus::method!(Index::acquire_index_writer, 1),
    )?;
    class.define_method(
        "__release_index_writer",
        magnus::method!(Index::release_index_writer, 0),
    )?;
    class.define_method("__commit", magnus::method!(Index::commit, 0))?;
    class.define_method("__reload", magnus::method!(Index::reload, 0))?;
    class.define_method("__search", magnus::method!(Index::search, 2))?;

    Ok(())
}
