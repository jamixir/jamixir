use erasure_coding::erasure_codec::{do_decode, do_encode};
use std::error::Error;

/// Create test data: [0, 1, 2, ..., size-1] (wrapping at 256)
fn test_data(size: usize) -> Vec<u8> {
    (0..size).map(|i| (i % 256) as u8).collect()
}

#[test]
fn test_encoding_produces_correct_shard_count() -> Result<(), Box<dyn Error>> {
    let data = test_data(100);

    // Tiny config: C=2 → V=6 shards
    let shards = do_encode(data.clone(), 2)?;
    assert_eq!(shards.len(), 6, "C=2 should produce V=6 shards");

    Ok(())
}

#[test]
fn test_roundtrip_with_all_original_shards() -> Result<(), Box<dyn Error>> {
    let data = test_data(32);
    let shards = do_encode(data.clone(), 2)?;

    // Use shards 0 and 1 (both original)
    let decoded = do_decode(
        vec![shards[0].clone(), shards[1].clone()],
        vec![0, 1],
        data.len(),
        2,
    )?;

    assert_eq!(decoded, data, "Roundtrip with original shards failed");
    Ok(())
}

#[test]
fn test_roundtrip_with_recovery_shards_only() -> Result<(), Box<dyn Error>> {
    let data = test_data(32);
    let shards = do_encode(data.clone(), 2)?;

    // Use shards 2 and 3 (both recovery)
    let decoded = do_decode(
        vec![shards[2].clone(), shards[3].clone()],
        vec![2, 3],
        data.len(),
        2,
    )?;

    assert_eq!(decoded, data, "Roundtrip with recovery shards failed");
    Ok(())
}

#[test]
fn test_roundtrip_with_mixed_shards() -> Result<(), Box<dyn Error>> {
    let data = test_data(32);
    let shards = do_encode(data.clone(), 2)?;

    // Use shard 0 (original) and shard 3 (recovery)
    let decoded = do_decode(
        vec![shards[0].clone(), shards[3].clone()],
        vec![0, 3],
        data.len(),
        2,
    )?;

    assert_eq!(decoded, data, "Roundtrip with mixed shards failed");
    Ok(())
}

#[test]
fn test_roundtrip_various_sizes() -> Result<(), Box<dyn Error>> {
    let test_cases = vec![1, 2, 3, 4, 10, 32, 100];

    for size in test_cases {
        let data = test_data(size);
        let shards = do_encode(data.clone(), 2)?;

        let decoded = do_decode(
            vec![shards[0].clone(), shards[1].clone()],
            vec![0, 1],
            data.len(),
            2,
        )?;

        assert_eq!(decoded, data, "Roundtrip failed for size={}", size);
    }
    Ok(())
}

#[test]
fn test_every_shard_combination() -> Result<(), Box<dyn Error>> {
    let data = test_data(20);
    let shards = do_encode(data.clone(), 2)?;

    // Test all 15 possible pairs of 6 shards
    for i in 0..6 {
        for j in (i + 1)..6 {
            let decoded = do_decode(
                vec![shards[i].clone(), shards[j].clone()],
                vec![i, j],
                data.len(),
                2,
            )?;

            assert_eq!(decoded, data, "Failed with shards [{}, {}]", i, j);
        }
    }
    Ok(())
}
