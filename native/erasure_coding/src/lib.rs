pub mod erasure_codec;

// Re-export the core functions for use by other Rust code
pub use erasure_codec::{do_decode, do_encode};

#[cfg(feature = "nif")]
use rustler::{Binary, NifResult};

#[cfg(feature = "nif")]
#[rustler::nif]
fn encode<'a>(
    env: rustler::Env<'a>,
    data_binary: Binary<'a>,
    c: usize,
) -> NifResult<Vec<Binary<'a>>> {
    let data = data_binary.as_slice().to_vec();
    let result = do_encode(data, c)
        .map(|shards| {
            shards
                .into_iter()
                .map(|shard| {
                    let mut owned_binary = rustler::OwnedBinary::new(shard.len()).unwrap();
                    owned_binary.as_mut_slice().copy_from_slice(&shard);
                    Binary::from_owned(owned_binary, env)
                })
                .collect()
        })
        .map_err(|_| rustler::Error::Atom("error"));

    result
}

#[cfg(feature = "nif")]
#[rustler::nif]
fn decode<'a>(
    env: rustler::Env<'a>,
    shards: Vec<Binary<'a>>,
    indexes: Vec<usize>,
    original_size: usize,
    c: usize,
) -> NifResult<Binary<'a>> {
    let shards_binaries: Vec<Vec<u8>> = shards
        .into_iter()
        .map(|shard| shard.as_slice().to_vec())
        .collect();
    let result = do_decode(shards_binaries, indexes, original_size, c)
        .map(|decoded| {
            let mut owned_binary = rustler::OwnedBinary::new(decoded.len()).unwrap();
            owned_binary.as_mut_slice().copy_from_slice(&decoded);
            Binary::from_owned(owned_binary, env)
        })
        .map_err(|_| rustler::Error::Atom("error"));

    result
}

#[cfg(feature = "nif")]
rustler::init!("Elixir.ErasureCoding");
