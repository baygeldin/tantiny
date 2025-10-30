use magnus::{Error, Module, Object, RModule, Ruby};
use tantivy::tokenizer::{
    LowerCaser, NgramTokenizer, RemoveLongFilter, SimpleTokenizer, Stemmer, TextAnalyzer,
};

use crate::helpers::LanguageWrapper;

#[magnus::wrap(class = "Tantiny::Tokenizer", free_immediately, size)]
pub struct Tokenizer(TextAnalyzer);

impl Tokenizer {
    pub fn get_analyzer(&self) -> TextAnalyzer {
        self.0.clone()
    }

    fn new_simple() -> Result<Self, Error> {
        let tokenizer = TextAnalyzer::builder(SimpleTokenizer::default())
            .filter(RemoveLongFilter::limit(40))
            .filter(LowerCaser)
            .build();
        Ok(Tokenizer(tokenizer))
    }

    fn new_stemmer(language: String) -> Result<Self, Error> {
        let lang_wrapper = LanguageWrapper::try_from(language)?;
        let tokenizer = TextAnalyzer::builder(SimpleTokenizer::default())
            .filter(RemoveLongFilter::limit(40))
            .filter(LowerCaser)
            .filter(Stemmer::new(lang_wrapper.0))
            .build();
        Ok(Tokenizer(tokenizer))
    }

    fn new_ngram(min_gram: i64, max_gram: i64, prefix_only: bool) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let tokenizer = NgramTokenizer::new(min_gram as usize, max_gram as usize, prefix_only)
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("Failed to create ngram tokenizer: {}", e),
                )
            })?;

        Ok(Tokenizer(TextAnalyzer::builder(tokenizer).build()))
    }

    fn extract_terms(&self, text: String) -> Result<Vec<String>, Error> {
        let mut cloned_analyzer = self.0.clone();
        let mut token_stream = cloned_analyzer.token_stream(&text);
        let mut terms = Vec::new();

        while token_stream.advance() {
            terms.push(token_stream.token().text.clone());
        }

        Ok(terms)
    }
}

pub fn init(ruby: &Ruby, module: RModule) -> Result<(), Error> {
    let class = module.define_class("Tokenizer", ruby.class_object())?;

    class.define_singleton_method(
        "__new_simple_tokenizer",
        magnus::function!(Tokenizer::new_simple, 0),
    )?;
    class.define_singleton_method(
        "__new_stemmer_tokenizer",
        magnus::function!(Tokenizer::new_stemmer, 1),
    )?;
    class.define_singleton_method(
        "__new_ngram_tokenizer",
        magnus::function!(Tokenizer::new_ngram, 3),
    )?;
    class.define_method(
        "__extract_terms",
        magnus::method!(Tokenizer::extract_terms, 1),
    )?;

    Ok(())
}
