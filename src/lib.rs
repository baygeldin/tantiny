mod helpers;
mod index;
mod query;
mod tokenizer;

use magnus::{Error, Ruby};

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("Tantiny")?;

    index::init(ruby, module)?;
    query::init(ruby, module)?;
    tokenizer::init(ruby, module)?;

    Ok(())
}
