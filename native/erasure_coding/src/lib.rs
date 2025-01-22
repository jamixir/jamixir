use reed_solomon::ReedSolomonEncoder;
use rustler::NifResult;

#[rustler::nif]
fn encode(data: Vec<Vec<u8>>) -> NifResult<Vec<Vec<u8>>> {
    let result = do_encode(data);

    result.map_err(|_| rustler::Error::Atom("error"))
}

fn do_encode(data: Vec<Vec<u8>>) -> Result<Vec<Vec<u8>>, reed_solomon::Error> {
    if data.len() != 342 {
        return Err(reed_solomon::Error::NotEnoughShards {
            original_count: 342,
            original_received_count: data.len(),
            recovery_received_count: 1023,
        });
    }

    // TODO this is temporary until we can get the erasure coding to work with 2 bytes
    let padded_data: Vec<Vec<u8>> = data
        .into_iter()
        .map(|v| {
            let mut padded = vec![0u8; 64]; // Create vector with 64 zeros
            padded[..v.len()].copy_from_slice(&v); // Copy original bytes to start
            padded
        })
        .collect();

    let mut encoder = ReedSolomonEncoder::new(
        342,  // total number of original shards
        1023, // total number of recovery shards
        64,   // shard size in bytes
    )?;

    for shard in padded_data {
        encoder.add_original_shard(shard)?;
    }

    // let result = reed_solomon::encode(382, 1023, data)?;
    let result = encoder.encode()?;

    let recovery: Vec<Vec<u8>> = result.recovery_iter().map(|s| s.to_vec()).collect();

    Ok(recovery)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode() {
        let data: Vec<Vec<u8>> = (1..=342)
            .map(|x: u16| vec![(x % 255) as u8, (x % 255) as u8])
            .collect();
        let result = do_encode(data).unwrap();
        assert_eq!(1, 1);
        assert_eq!(result.len(), 1023);
    }
}

rustler::init!("Elixir.ErasureCoding");
