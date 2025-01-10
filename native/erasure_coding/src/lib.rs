use reed_solomon::ReedSolomonEncoder;
use rustler::NifResult;

#[rustler::nif]
fn encode(data: Vec<Vec<u8>>) -> NifResult<Vec<Vec<u8>>> {
    let result = do_encode(data);

    result.map_err(|e| rustler::Error::Atom("error"))
}

fn do_encode(data: Vec<Vec<u8>>) -> Result<Vec<Vec<u8>>, reed_solomon::Error> {
    let original_count = data.len();
    println!("line 1");
    let mut encoder = ReedSolomonEncoder::new(
        original_count,  // total number of original shards
        1023, // total number of recovery shards
        684 as usize,  // shard size in bytes
    )?;
    println!("line 2");

    for shard in data {
        encoder.add_original_shard(shard)?;
    }
    println!("line 3");

    let result = encoder.encode()?;

    let recovery: Vec<Vec<u8>> = result.recovery_iter().map(|s| s.to_vec()).collect();

    Ok(recovery)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode() {
        let data: Vec<u8> = (1..=684).map(|x| (x % 256) as u8).collect();
        let result = do_encode(vec![data]).unwrap();
      assert_eq!(1, 1);
        assert_eq!(result.len(), 1023);
    }
}

rustler::init!("Elixir.ErasureCoding");
