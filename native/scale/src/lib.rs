use parity_scale_codec::{Compact, Decode, Encode};
use rustler::{Env, NifResult, Term};

#[rustler::nif]
fn encode_integer(number: u64) -> NifResult<Vec<u8>> {
    let mut encoded = Vec::new();
    Compact(number).encode_to(&mut encoded);
    Ok(encoded)
}

#[rustler::nif]
fn decode_integer<'a>(v: Vec<u8>) -> NifResult<u64> {
    let decoded = Compact::<u64>::decode(&mut &v[..]).unwrap();
    Ok(decoded.into())
}

rustler::init!("Elixir.ScaleNative");
