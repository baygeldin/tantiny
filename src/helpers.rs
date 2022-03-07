use std::collections::HashMap;
use rutie::{AnyException, Array, Exception, RString, Hash, Integer, Float, Boolean, Module};
use tantivy::schema::{Field};
use tantivy::tokenizer::Language;

// Macro dependencies:
pub(super) use paste::paste;
pub(super) use rutie::{class, wrappable_struct, AnyObject, VerifiedObject, VM, Object, Class};

pub(crate) fn namespace() -> Module {
    Module::from_existing("Tantiny")
}

pub(crate) struct LanguageWrapper(pub(crate) Language);

impl std::str::FromStr for LanguageWrapper {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "en" => Ok(LanguageWrapper(Language::English)),
            "ar" => Ok(LanguageWrapper(Language::Arabic)),
            "da" => Ok(LanguageWrapper(Language::Danish)),
            "nl" => Ok(LanguageWrapper(Language::Dutch)),
            "fi" => Ok(LanguageWrapper(Language::Finnish)),
            "fr" => Ok(LanguageWrapper(Language::French)),
            "de" => Ok(LanguageWrapper(Language::German)),
            "el" => Ok(LanguageWrapper(Language::Greek)),
            "hu" => Ok(LanguageWrapper(Language::Hungarian)),
            "it" => Ok(LanguageWrapper(Language::Italian)),
            "no" => Ok(LanguageWrapper(Language::Norwegian)),
            "pt" => Ok(LanguageWrapper(Language::Portuguese)),
            "ro" => Ok(LanguageWrapper(Language::Romanian)),
            "ru" => Ok(LanguageWrapper(Language::Russian)),
            "es" => Ok(LanguageWrapper(Language::Spanish)),
            "sv" => Ok(LanguageWrapper(Language::Swedish)),
            "ta" => Ok(LanguageWrapper(Language::Tamil)),
            "tr" => Ok(LanguageWrapper(Language::Turkish)),
            _ => Err(format!("Language '{}' is not supported.", s)),
        }
    }
}

pub(crate) trait TryUnwrap<T> {
    fn try_unwrap(self) -> T;
}

macro_rules! primitive_try_unwrap_impl {
    ( $ruby_type:ty, $type:ty ) => {
        paste! {
            impl TryUnwrap<$type> for $ruby_type {
                fn try_unwrap(self) -> $type {
                    self.[<to_ $type:lower>]()
                }
            }

            impl TryUnwrap<$type> for AnyObject {
                fn try_unwrap(self) -> $type {
                    self.try_convert_to::<$ruby_type>()
                        .try_unwrap()
                        .[<to_ $type:lower>]()
                }
            }
        }
    };
}

primitive_try_unwrap_impl!(RString, String);
primitive_try_unwrap_impl!(Integer, i64);
primitive_try_unwrap_impl!(Float, f64);
primitive_try_unwrap_impl!(Boolean, bool);

impl<T> TryUnwrap<Vec<T>> for Array where
    AnyObject: TryUnwrap<T>
{
    fn try_unwrap(self) -> Vec<T> {
        let mut vec = Vec::new();

        for elem in self {
            vec.push(elem.try_unwrap());
        }

        vec
    }
}

impl<K, V> TryUnwrap<HashMap<K, V>> for Hash where
    AnyObject: TryUnwrap<K> + TryUnwrap<V>,
    K: Eq + std::hash::Hash
{
    fn try_unwrap(self) -> HashMap<K, V> {
        let mut hashmap = HashMap::new();

        self.each(|key, value| {
            hashmap.insert(key.try_unwrap(), value.try_unwrap());
        });

        hashmap
    }
}

impl<T, E> TryUnwrap<T> for Result<T, E>
where
    E: ToString,
{
    fn try_unwrap(self) -> T {
        self.map_err(|e| {
            VM::raise_ex(AnyException::new(
                "Tantiny::TantivyError",
                Some(&e.to_string()),
            ))
        })
        .unwrap()
    }
}

impl TryUnwrap<Field> for Option<Field> {
    fn try_unwrap(self) -> Field {
        if let Some(value) = self {
            value
        } else {
            VM::raise_ex(AnyException::new("Tantiny::UnknownField", None));

            self.unwrap()
        }
    }
}

macro_rules! try_unwrap_params {
    (
        $param:ident: $type:ty,
        $( $rest:tt )*
    ) => {
        let _tmp = $param.map_err(|e| $crate::helpers::VM::raise_ex(e)).unwrap();
        let $param = <_ as $crate::helpers::TryUnwrap<$type>>::try_unwrap(_tmp);

        try_unwrap_params!($($rest)*)
    };
    (
        $param:ident,
        $( $rest:tt )*
    ) => {
        let $param = $param.map_err(|e| $crate::helpers::VM::raise_ex(e)).unwrap();

        try_unwrap_params!($($rest)*)
    };

    // Handle optional trailing commas.
    ( $param:ident: $type:ty ) => {
        try_unwrap_params!($param: $type,)
    };
    ( $param:ident ) => {
        try_unwrap_params!($param,)
    };

    () => {}
}

pub(crate) use try_unwrap_params;

macro_rules! scaffold {
    ( $ruby_type:ident, $type:ty, $klass:literal ) => {
        $crate::helpers::class!($ruby_type);

        // There is a bug in Rutie which prevents using this macro
        // by resolving it by a full path, so the only workaround is:
        use crate::helpers::wrappable_struct;
         
        $crate::helpers::paste! {
            wrappable_struct!(
                $type,
                [<$type Wrapper>],
                [<$type:snake:upper _WRAPPER>]
            );
        }

        pub(crate) fn klass() -> $crate::helpers::Class {
            $crate::helpers::namespace().get_nested_class($klass)
        }

        impl $crate::helpers::TryUnwrap<$ruby_type> for $crate::helpers::AnyObject {
            fn try_unwrap(self) -> $ruby_type {
                let result = self.try_convert_to::<$ruby_type>();
                <_ as $crate::helpers::TryUnwrap<$ruby_type>>::try_unwrap(result)
            }
        }

        impl $crate::helpers::VerifiedObject for $ruby_type {
            fn is_correct_type<T: $crate::helpers::Object>(object: &T) -> bool {
                object.class() == klass()
            }

            fn error_message() -> &'static str {
                concat!("Error converting to ", stringify!($ruby_type), ".")
            }
        }
    }
}

pub(crate) use scaffold;