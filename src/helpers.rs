use magnus::{r_hash::ForEach, Error, RHash, Ruby, TryConvert, Value};
use std::collections::HashMap;

pub fn hash_to_hashmap<K, V>(hash: RHash) -> Result<HashMap<K, V>, Error>
where
    K: std::cmp::Eq + std::hash::Hash + TryConvert,
    V: TryConvert,
{
    let mut map = HashMap::new();

    hash.foreach(|key: Value, value: Value| {
        let ruby = unsafe { Ruby::get_unchecked() };
        let k: K = K::try_convert(key)
            .map_err(|_| Error::new(ruby.exception_runtime_error(), "Key conversion failed"))?;
        let v: V = V::try_convert(value)
            .map_err(|_| Error::new(ruby.exception_runtime_error(), "Value conversion failed"))?;
        map.insert(k, v);
        Ok(ForEach::Continue)
    })?;

    Ok(map)
}

use tantivy::tokenizer::Language;

pub struct LanguageWrapper(pub Language);

impl TryFrom<String> for LanguageWrapper {
    type Error = Error;

    fn try_from(s: String) -> Result<Self, Self::Error> {
        let lang = match s.as_str() {
            "en" => Language::English,
            "ar" => Language::Arabic,
            "da" => Language::Danish,
            "nl" => Language::Dutch,
            "fi" => Language::Finnish,
            "fr" => Language::French,
            "de" => Language::German,
            "el" => Language::Greek,
            "hu" => Language::Hungarian,
            "it" => Language::Italian,
            "no" => Language::Norwegian,
            "pt" => Language::Portuguese,
            "ro" => Language::Romanian,
            "ru" => Language::Russian,
            "es" => Language::Spanish,
            "sv" => Language::Swedish,
            "ta" => Language::Tamil,
            "tr" => Language::Turkish,
            _ => {
                let ruby = unsafe { Ruby::get_unchecked() };
                return Err(Error::new(
                    ruby.exception_runtime_error(),
                    format!("Language '{}' is not supported.", s),
                ));
            }
        };
        Ok(LanguageWrapper(lang))
    }
}
