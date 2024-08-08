use parity_scale_codec::{Compact, Encode};
use rustler::{Env, NifResult, Term};

#[rustler::nif]
fn encode_compact_integer(number: u64) -> NifResult<Vec<u8>> {
    let mut encoded = Vec::new();
    Compact(number).encode_to(&mut encoded);
    Ok(encoded)
}

#[rustler::nif]
fn add(a: i64, b: i64) -> i64 {
    a + b
}

rustler::init!("Elixir.Scale");
