mod helpers;
#[allow(improper_ctypes_definitions)]
mod index;
#[allow(improper_ctypes_definitions)]
mod query;

#[allow(improper_ctypes_definitions)]
mod tokenizer;

#[no_mangle]
pub extern "C" fn init_tantiny() {
    index::init();
    query::init();
    tokenizer::init();
}