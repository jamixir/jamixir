#![allow(non_snake_case)]

use rustler::{Atom, Binary, Env, NifResult, OwnedBinary};

rustler::atoms! {
    ok,
    error,
    lower,
    upper,
}

#[derive(PartialEq)]
enum Case {
    Lower,
    Upper,
}

impl From<Option<Atom>> for Case {
    fn from(atom: Option<Atom>) -> Self {
        match atom {
            Some(atom) if atom == lower() => Case::Lower,
            Some(atom) if atom == upper() => Case::Upper,
            _ => Case::Lower, // Default case
        }
    }
}

/// Hex encoding and decoding functions
/// Provides fast native implementations for hex operations

#[rustler::nif]
fn encode16<'a>(data: Binary<'a>, case: Option<Atom>) -> String {
    let data_bytes = data.as_slice();
    let case: Case = case.into();

    if case == Case::Upper {
        hex::encode_upper(data_bytes)
    } else {
        hex::encode(data_bytes)
    }
}

#[rustler::nif]
fn decode16<'a>(env: Env<'a>, hex_str: String) -> NifResult<(Atom, Binary<'a>)> {
    // Handle optional "0x" prefix
    let clean_hex = if hex_str.starts_with("0x") || hex_str.starts_with("0X") {
        &hex_str[2..]
    } else {
        &hex_str
    };

    let decoded_bytes = hex::decode(clean_hex).map_err(|_| rustler::Error::Atom("invalid_hex"))?;

    let mut owned_binary = OwnedBinary::new(decoded_bytes.len()).unwrap();
    owned_binary.as_mut_slice().copy_from_slice(&decoded_bytes);
    Ok((ok(), Binary::from_owned(owned_binary, env)))
}

rustler::init!("Elixir.Util.HexNative");
