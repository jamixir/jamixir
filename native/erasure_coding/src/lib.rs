#![allow(non_snake_case)]

use reed_solomon_simd::{ReedSolomonDecoder, ReedSolomonEncoder};
use rustler::NifResult;
use std::error::Error;

use rustler::Binary;

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

fn do_encode(mut d_bytes: Vec<u8>, C: usize) -> Result<Vec<Vec<u8>>, Box<dyn Error>> {
    let W_E = C * 2;
    let d_bytes_len = d_bytes.len();
    if d_bytes_len % W_E != 0 {
        let pad_len = W_E - (d_bytes.len() % W_E);
        d_bytes.extend(std::iter::repeat(0).take(pad_len));
    }

    let k = d_bytes.len() / W_E;

    let mut original_shards = vec![Vec::with_capacity(W_E); C];
    for i in 0..k {
        for c in 0..C {
            original_shards[c].push(d_bytes[i * W_E + c * 2]);
            original_shards[c].push(d_bytes[i * W_E + c * 2 + 1]);
        }
    }

    let mut encoder = ReedSolomonEncoder::new(C, C * 2, 2 * k)?;
    let mut shards = Vec::new();

    for shard in &original_shards {
        encoder.add_original_shard(shard)?;
        shards.push(shard.clone());
    }

    let result = encoder.encode()?;
    let recovery: Vec<_> = result.recovery_iter().collect();
    if recovery.len() != C * 2 {
        panic!("Expected {} recovery shards, got {}", C * 2, recovery.len());
    }

    for r in &recovery {
        shards.push(r.to_vec());
    }

    Ok(shards)
}

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

fn do_decode(
    shards: Vec<Vec<u8>>,
    indexes: Vec<usize>,
    original_size: usize,
    C: usize,
) -> Result<Vec<u8>, Box<dyn Error>> {
    let W_E = C * 2;

    let mut pad_len = 0;
    if original_size % W_E != 0 {
        pad_len = W_E - (original_size % W_E);
    }
    let k = (original_size + pad_len) / W_E;
    let mut decoder = ReedSolomonDecoder::new(C, 2 * C, k * 2)?;

    let mut recovered_shards = vec![vec![0u8; k * 2]; C];

    for (i, shard) in shards.iter().enumerate() {
        let bytes = shard.as_slice();
        if indexes[i] < C {
            decoder.add_original_shard(indexes[i], bytes)?;
            recovered_shards[indexes[i]].copy_from_slice(bytes);
        } else {
            decoder.add_recovery_shard(indexes[i] - C, bytes)?;
        }
    }

    let decoded = decoder.decode()?;
    for (index, segment) in decoded.restored_original_iter() {
        recovered_shards[index].copy_from_slice(segment);
    }
    let mut reconstructed: Vec<u8> = Vec::with_capacity(k * W_E);
    for i in 0..k {
        for c in 0..C {
            reconstructed.push(recovered_shards[c][2 * i]); // low byte
            reconstructed.push(recovered_shards[c][2 * i + 1]); // high byte
        }
    }
    // Clip to the expected length
    let trimmed = &reconstructed[..original_size];
    Ok(trimmed.into())
}

rustler::init!("Elixir.ErasureCoding");

#[cfg(test)]
mod tests {
    use super::*;
    use hex;
    use std::error::Error;

    #[test]
    fn test_my_encode_decode() -> Result<(), Box<dyn Error>> {
        let bytes = vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        let result = do_encode(bytes.clone(), 2)?;
        let decoded = do_decode(
            vec![result[0].clone(), result[1].clone()],
            vec![0, 1],
            10,
            2,
        )?;
        assert_eq!(decoded, bytes);
        Ok(())
    }

    #[test]
    fn test_my_encode_decode272tiny() -> Result<(), Box<dyn Error>> {
        let b272 = "0x0000000000fa002583136a79daec5ca5e802d27732517c3f7dc4970dc2d68abcaad891e99d001fd1664d60a77f32449f2ed9898f3eb0fef21ba0537b014276f7ff7042355c3a8f001f0b92def425b5cbd7c14118f67d99654e26894a76187f453631503f120cfee77aea940e38601cb828d2878308e32529f8382cf85f7a29b75f1c826985bc1db7f36f81fc164ee563dc27b8e940a40f8c4bc334fe5964678b1ed8cc848f6111451f0000010000000028a0e0c33fcc7cadbb6627bcc902064e89ba1d16c26ea88371a4f614942fb8372906e90be226abaccc638a0addae983f814190ba97367f8abc5e21642a1e48f23d57724100000000000000105e5f000000008096980000000000000000000000";
        let bytes = hex::decode(b272.trim_start_matches("0x"))?;
        let result = do_encode(bytes.clone(), 2)?;
        let decoded = do_decode(
            vec![result[3].clone(), result[5].clone()],
            vec![3, 5],
            272,
            2,
        )?;
        assert_eq!(decoded, bytes);
        Ok(())
    }
}
