
use rutie::{methods, Object, Array, RString, Integer, Boolean};
use tantivy::tokenizer::{TextAnalyzer, SimpleTokenizer, RemoveLongFilter, LowerCaser, Stemmer, NgramTokenizer};

use crate::helpers::{try_unwrap_params, scaffold, TryUnwrap, LanguageWrapper};

pub struct TantinyTokenizer(pub(crate) TextAnalyzer);

scaffold!(RTantinyTokenizer, TantinyTokenizer, "Tokenizer");

fn wrap_tokenizer(tokenizer: TextAnalyzer) -> RTantinyTokenizer {
    klass().wrap_data(
        TantinyTokenizer(tokenizer),
        &*TANTINY_TOKENIZER_WRAPPER
    )
}

pub(crate) fn unwrap_tokenizer(tokenizer: &RTantinyTokenizer) -> &TextAnalyzer {
    &tokenizer.get_data(&*TANTINY_TOKENIZER_WRAPPER).0
}

#[rustfmt::skip::macros(methods)]
methods!(
    RTantinyTokenizer,
    _itself,

    fn new_simple_tokenizer() -> RTantinyTokenizer {
        let tokenizer = TextAnalyzer::from(SimpleTokenizer)
            .filter(RemoveLongFilter::limit(40))
            .filter(LowerCaser);

        wrap_tokenizer(tokenizer)
    }

    fn new_stemmer_tokenizer(locale_code: RString) -> RTantinyTokenizer {
        try_unwrap_params!(locale_code: String);

        let language: LanguageWrapper = locale_code.parse().try_unwrap();
        let tokenizer = TextAnalyzer::from(SimpleTokenizer)
            .filter(RemoveLongFilter::limit(40))
            .filter(LowerCaser)
            .filter(Stemmer::new(language.0));

        wrap_tokenizer(tokenizer)
    }

    fn new_ngram_tokenizer(
        min_gram: Integer,
        max_gram: Integer,
        prefix_only: Boolean
    ) -> RTantinyTokenizer {
        try_unwrap_params!(
            min_gram: i64,
            max_gram: i64,
            prefix_only: bool
        );

        let tokenizer = NgramTokenizer::new(
            min_gram as usize,
            max_gram as usize,
            prefix_only
        );

        wrap_tokenizer(TextAnalyzer::from(tokenizer))
    }

    fn extract_terms(text: RString) -> Array {
        try_unwrap_params!(text: String);

        let mut token_stream = unwrap_tokenizer(&_itself).token_stream(&text);
        let mut terms = vec![];

        while token_stream.advance() {
            terms.push(token_stream.token().clone().text);
        }

        let mut array = Array::with_capacity(terms.len());

        for term in terms {
            array.push(RString::from(term));
        }

        array
    }
);

pub(super) fn init() {
    klass().define(|klass| {
        klass.def_self("__new_simple_tokenizer", new_simple_tokenizer);
        klass.def_self("__new_stemmer_tokenizer", new_stemmer_tokenizer);
        klass.def_self("__new_ngram_tokenizer", new_ngram_tokenizer);
        klass.def("__extract_terms", extract_terms);
    });
} 