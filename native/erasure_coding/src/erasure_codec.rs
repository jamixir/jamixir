use reed_solomon_simd::{ReedSolomonDecoder, ReedSolomonEncoder};
use std::error::Error;

// Reed-Solomon Configuration Constants

const RECOVERY_SHARD_MULTIPLIER: usize = 2; // Each data shard gets 2 recovery shards
const BYTES_PER_SYMBOL: usize = 2; // Each symbol is 2 bytes (16-bit)
const PADDING_BYTE: u8 = 0; // Padding value for incomplete symbols
const ZERO_BYTE: u8 = 0; // Default byte value for shard initialization

/// Calculate how many bytes of padding are needed to align data with symbol boundaries
fn calculate_padding_needed(data_size: usize, num_data_shards: usize) -> usize {
    let bytes_per_data_chunk = num_data_shards * BYTES_PER_SYMBOL;
    if data_size % bytes_per_data_chunk == 0 {
        0
    } else {
        bytes_per_data_chunk - (data_size % bytes_per_data_chunk)
    }
}

fn split_data_into_shards(
    input_data: &[u8],
    num_data_shards: usize,
    symbols_per_shard: usize,
) -> Vec<Vec<u8>> {
    let bytes_per_data_chunk = num_data_shards * BYTES_PER_SYMBOL;
    let mut data_shards = vec![Vec::with_capacity(bytes_per_data_chunk); num_data_shards];

    for symbol_index in 0..symbols_per_shard {
        for shard_index in 0..num_data_shards {
            let byte_offset = symbol_index * bytes_per_data_chunk + shard_index * BYTES_PER_SYMBOL;
            data_shards[shard_index].push(input_data[byte_offset]);
            data_shards[shard_index].push(input_data[byte_offset + 1]);
        }
    }

    data_shards
}

fn reconstruct_data_from_shards(
    data_shards: &[Vec<u8>],
    num_data_shards: usize,
    symbols_per_shard: usize,
    original_data_size: usize,
) -> Vec<u8> {
    let bytes_per_data_chunk = num_data_shards * BYTES_PER_SYMBOL;
    let mut reconstructed_bytes: Vec<u8> =
        Vec::with_capacity(symbols_per_shard * bytes_per_data_chunk);

    for symbol_index in 0..symbols_per_shard {
        for data_shard_index in 0..num_data_shards {
            let byte_offset = BYTES_PER_SYMBOL * symbol_index;
            reconstructed_bytes.push(data_shards[data_shard_index][byte_offset]); // low byte
            reconstructed_bytes.push(data_shards[data_shard_index][byte_offset + 1]);
            // high byte
        }
    }

    // Remove padding to return data to original size
    reconstructed_bytes.truncate(original_data_size);
    reconstructed_bytes
}

/// Validate recovery shard count matches expected count
fn validate_recovery_shard_count(recovery_shards: &[&[u8]], num_data_shards: usize) {
    let expected_count = num_data_shards * RECOVERY_SHARD_MULTIPLIER;
    if recovery_shards.len() != expected_count {
        panic!(
            "Expected {} recovery shards, got {}",
            expected_count,
            recovery_shards.len()
        );
    }
}

pub fn do_encode(
    mut input_data: Vec<u8>,
    num_data_shards: usize,
) -> Result<Vec<Vec<u8>>, Box<dyn Error>> {
    let V = if num_data_shards == 2 { 6 } else { 1023 };
    let bytes_per_data_chunk = num_data_shards * BYTES_PER_SYMBOL;
    let input_length = input_data.len();

    // Pad input data to align with symbol boundaries
    let padding_needed = calculate_padding_needed(input_length, num_data_shards);
    if padding_needed > 0 {
        input_data.extend(std::iter::repeat(PADDING_BYTE).take(padding_needed));
    }

    let shard_size = input_data.len() / num_data_shards;
    let symbols_per_shard = input_data.len() / bytes_per_data_chunk;
    let mut original_shards: Vec<Vec<u8>> = vec![Vec::with_capacity(2 * symbols_per_shard); num_data_shards];
    let mut recovery_shards: Vec<Vec<u8>> = vec![Vec::with_capacity(2 * symbols_per_shard); V - num_data_shards];

    let data_shards = split_data_into_shards(&input_data, num_data_shards, symbols_per_shard);

    for i in 0..symbols_per_shard {
        let mut encoder = ReedSolomonEncoder::new(
            num_data_shards,
            V - num_data_shards,
            BYTES_PER_SYMBOL
        )?;
        for c in 0..num_data_shards {
            let shard = [
                input_data[i * BYTES_PER_SYMBOL + c * shard_size],
                input_data[i * BYTES_PER_SYMBOL + c * shard_size + 1]
            ];
            encoder.add_original_shard(&shard)?;
            original_shards[c].extend_from_slice(&shard);
        }
        let encoded = encoder.encode()?;
        for (j, shard) in encoded.recovery_iter().enumerate() {
            recovery_shards[j].extend_from_slice(shard);
        }


    }
    let all_shards = original_shards
                .iter()
                .chain(recovery_shards.iter()).map(|s| s.clone()).collect();

    Ok(all_shards)
}

pub fn do_decode(
    input_shards: Vec<Vec<u8>>,
    shard_indexes: Vec<usize>,
    original_data_size: usize,
    num_data_shards: usize,
) -> Result<Vec<u8>, Box<dyn Error>> {
    let bytes_per_data_chunk = num_data_shards * BYTES_PER_SYMBOL;

    let padding_length = calculate_padding_needed(original_data_size, num_data_shards);

    let symbols_per_shard = (original_data_size + padding_length) / bytes_per_data_chunk;
    let mut decoder = ReedSolomonDecoder::new(
        num_data_shards,
        RECOVERY_SHARD_MULTIPLIER * num_data_shards,
        symbols_per_shard * BYTES_PER_SYMBOL,
    )?;

    let mut reconstructed_data_shards =
        vec![vec![ZERO_BYTE; symbols_per_shard * BYTES_PER_SYMBOL]; num_data_shards];

    for (shard_position, shard_data) in input_shards.iter().enumerate() {
        let shard_bytes = shard_data.as_slice();
        let shard_index = shard_indexes[shard_position];

        if shard_index < num_data_shards {
            // This is a data shard
            decoder.add_original_shard(shard_index, shard_bytes)?;
            reconstructed_data_shards[shard_index].copy_from_slice(shard_bytes);
        } else {
            // This is a recovery shard
            let recovery_index = shard_index - num_data_shards;
            decoder.add_recovery_shard(recovery_index, shard_bytes)?;
        }
    }

    let decoding_result = decoder.decode()?;
    for (data_shard_index, restored_shard_data) in decoding_result.restored_original_iter() {
        reconstructed_data_shards[data_shard_index].copy_from_slice(restored_shard_data);
    }

    // Reconstruct the original data from the data shards
    let final_data = reconstruct_data_from_shards(
        &reconstructed_data_shards,
        num_data_shards,
        symbols_per_shard,
        original_data_size,
    );

    Ok(final_data)
}

#[cfg(test)]
mod tests {
    use super::*;
    use hex;

    // Helper function for testing
    fn create_test_data(size: usize) -> Vec<u8> {
        (0..size).map(|i| (i % 256) as u8).collect()
    }

    #[test]
    fn test_shard_count_assertion() -> Result<(), Box<dyn Error>> {
        let data = create_test_data(100);

        // Test different values of C
        for c in [1, 2, 3, 4, 5] {
            let shards = do_encode(data.clone(), c)?;
            // Should always produce C * 3 total shards (C data + 2*C recovery)
            assert_eq!(
                shards.len(),
                c * 3,
                "C={}: Expected {} shards, got {}",
                c,
                c * 3,
                shards.len()
            );
        }
        Ok(())
    }

    #[test]
    fn test_c_equals_one_minimal_case() -> Result<(), Box<dyn Error>> {
        let data = vec![1, 2]; // Small data for C=1
        let shards = do_encode(data.clone(), 1)?;

        // Should produce 3 shards (1 data + 2 recovery)
        assert_eq!(shards.len(), 3);

        // Should be able to recover from any single shard
        for i in 0..3 {
            let decoded = do_decode(vec![shards[i].clone()], vec![i], data.len(), 1)?;
            assert_eq!(decoded, data, "Failed to recover from shard {}", i);
        }
        Ok(())
    }

    #[test]
    fn test_recovery_from_exactly_c_shards() -> Result<(), Box<dyn Error>> {
        let data = create_test_data(50);

        for c in [2, 3, 4] {
            let shards = do_encode(data.clone(), c)?;

            // Test recovery from first C shards (all data shards)
            let first_c_shards: Vec<_> = shards[0..c].to_vec();
            let first_c_indexes: Vec<_> = (0..c).collect();

            let decoded = do_decode(first_c_shards, first_c_indexes, data.len(), c)?;
            assert_eq!(
                decoded, data,
                "Failed to recover from first C data shards with C={}",
                c
            );

            // Test recovery from last C shards (mix of data and recovery)
            let last_c_shards: Vec<_> = shards[(c * 3 - c)..].to_vec();
            let last_c_indexes: Vec<_> = ((c * 3 - c)..(c * 3)).collect();

            let decoded = do_decode(last_c_shards, last_c_indexes, data.len(), c)?;
            assert_eq!(
                decoded, data,
                "Failed to recover from last C shards with C={}",
                c
            );
        }
        Ok(())
    }

    #[test]
    fn test_recovery_from_more_than_c_shards() -> Result<(), Box<dyn Error>> {
        let data = create_test_data(40);
        let c = 2;
        let shards = do_encode(data.clone(), c)?;

        // Try with C+1 shards
        let extra_shards: Vec<_> = shards[0..c + 1].to_vec();
        let extra_indexes: Vec<_> = (0..c + 1).collect();

        let decoded = do_decode(extra_shards, extra_indexes, data.len(), c)?;
        assert_eq!(decoded, data, "Failed to recover with more than C shards");

        // Try with all shards
        let all_indexes: Vec<_> = (0..shards.len()).collect();
        let decoded = do_decode(shards, all_indexes, data.len(), c)?;
        assert_eq!(decoded, data, "Failed to recover with all shards");

        Ok(())
    }

    #[test]
    fn test_failure_with_less_than_c_shards() {
        let data = create_test_data(30);
        let c = 3;
        let shards = do_encode(data.clone(), c).unwrap();

        // Try with C-1 shards (should fail)
        let insufficient_shards: Vec<_> = shards[0..c - 1].to_vec();
        let insufficient_indexes: Vec<_> = (0..c - 1).collect();

        let result = do_decode(insufficient_shards, insufficient_indexes, data.len(), c);
        assert!(
            result.is_err(),
            "Should fail with insufficient shards (C-1)"
        );

        // Try with just 1 shard when C=3 (should fail)
        let single_shard = vec![shards[0].clone()];
        let single_index = vec![0];

        let result = do_decode(single_shard, single_index, data.len(), c);
        assert!(result.is_err(), "Should fail with only 1 shard when C=3");
    }

    #[test]
    fn test_mixed_data_and_recovery_shard_combinations() -> Result<(), Box<dyn Error>> {
        let data = create_test_data(60);
        let c = 3;
        let shards = do_encode(data.clone(), c)?;

        // Test various combinations of exactly C shards
        let test_combinations = vec![
            // All data shards
            (vec![0, 1, 2], "all data shards"),
            // All recovery shards
            (vec![3, 4, 5], "all recovery shards"),
            // Mix of data and recovery
            (vec![0, 1, 3], "data[0,1] + recovery[0]"),
            (vec![0, 4, 5], "data[0] + recovery[1,2]"),
            (vec![1, 2, 4], "data[1,2] + recovery[1]"),
            // Different recovery shards
            (vec![3, 4, 6], "recovery[0,1] + recovery[3]"),
            (vec![3, 5, 7], "recovery[0,2] + recovery[4]"),
        ];

        for (indexes, description) in test_combinations {
            let test_shards: Vec<_> = indexes.iter().map(|&i| shards[i].clone()).collect();

            let decoded = do_decode(test_shards, indexes.clone(), data.len(), c)?;
            assert_eq!(
                decoded, data,
                "Failed to recover from {}: {:?}",
                description, indexes
            );
        }

        Ok(())
    }

    #[test]
    fn test_different_data_sizes_with_various_c() -> Result<(), Box<dyn Error>> {
        let test_cases = vec![
            (1, 2),    // Very small data, C=1
            (10, 2),   // Small data, C=2
            (100, 3),  // Medium data, C=3
            (1000, 4), // Large data, C=4
            (7, 2),    // Odd size with C=2
            (13, 3),   // Prime size with C=3
        ];

        for (data_size, c) in test_cases {
            let data = create_test_data(data_size);
            let shards = do_encode(data.clone(), c)?;

            // Verify shard count
            assert_eq!(shards.len(), c * 3);

            // Test recovery from minimum required shards
            let test_shards: Vec<_> = shards[0..c].to_vec();
            let test_indexes: Vec<_> = (0..c).collect();

            let decoded = do_decode(test_shards, test_indexes, data.len(), c)?;
            assert_eq!(
                decoded, data,
                "Failed roundtrip with data_size={}, C={}",
                data_size, c
            );
        }

        Ok(())
    }

    #[test]
    fn test_simple_data_round_trip() -> Result<(), Box<dyn Error>> {
        let bytes = vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        let shards = do_encode(bytes.clone(), 2)?;
        let decoded = do_decode(
            vec![shards[0].clone(), shards[1].clone()],
            vec![0, 1],
            10,
            2,
        )?;
        assert_eq!(decoded, bytes);
        Ok(())
    }

    #[test]
    fn test_large_data_recovery_from_partial_shards() -> Result<(), Box<dyn Error>> {
        let hex_data = "0x0000000000fa002583136a79daec5ca5e802d27732517c3f7dc4970dc2d68abcaad891e99d001fd1664d60a77f32449f2ed9898f3eb0fef21ba0537b014276f7ff7042355c3a8f001f0b92def425b5cbd7c14118f67d99654e26894a76187f453631503f120cfee77aea940e38601cb828d2878308e32529f8382cf85f7a29b75f1c826985bc1db7f36f81fc164ee563dc27b8e940a40f8c4bc334fe5964678b1ed8cc848f6111451f0000010000000028a0e0c33fcc7cadbb6627bcc902064e89ba1d16c26ea88371a4f614942fb8372906e90be226abaccc638a0addae983f814190ba97367f8abc5e21642a1e48f23d57724100000000000000105e5f000000008096980000000000000000000000";
        let bytes = hex::decode(hex_data.trim_start_matches("0x"))?;
        let shards = do_encode(bytes.clone(), 2)?;

        // Test recovery using recovery shards (indexes 3 and 5 are recovery shards)
        let decoded = do_decode(
            vec![shards[3].clone(), shards[5].clone()],
            vec![3, 5],
            272,
            2,
        )?;
        assert_eq!(decoded, bytes);
        Ok(())
    }

    #[test]
    fn test_padding_scenarios() -> Result<(), Box<dyn Error>> {
        // Test various padding scenarios explicitly
        let test_cases = vec![
            // (data_size, num_data_shards, expected_padding, description)
            (1, 1, 1, "1 byte with C=1 needs 1 byte padding"), // 1 % 2 = 1
            (3, 1, 1, "3 bytes with C=1 needs 1 byte padding"), // 3 % 2 = 1
            (1, 2, 3, "1 byte with C=2 needs 3 bytes padding"), // 1 % 4 = 1
            (2, 2, 2, "2 bytes with C=2 needs 2 bytes padding"), // 2 % 4 = 2
            (3, 2, 1, "3 bytes with C=2 needs 1 byte padding"), // 3 % 4 = 3
            (5, 2, 3, "5 bytes with C=2 needs 3 bytes padding"), // 5 % 4 = 1
            (7, 3, 5, "7 bytes with C=3 needs 5 bytes padding"), // 7 % 6 = 1
            (11, 3, 1, "11 bytes with C=3 needs 1 byte padding"), // 11 % 6 = 5
            (13, 4, 3, "13 bytes with C=4 needs 3 bytes padding"), // 13 % 8 = 5
        ];

        for (data_size, num_data_shards, expected_padding, description) in test_cases {
            let original_data = create_test_data(data_size);
            let bytes_per_data_chunk = num_data_shards * BYTES_PER_SYMBOL;

            // Verify our padding calculation
            let calculated_padding = if data_size % bytes_per_data_chunk == 0 {
                0
            } else {
                bytes_per_data_chunk - (data_size % bytes_per_data_chunk)
            };
            assert_eq!(calculated_padding, expected_padding, "{}", description);

            // Test encode/decode round trip with padding
            let shards = do_encode(original_data.clone(), num_data_shards)?;

            // Verify total shards count
            assert_eq!(shards.len(), num_data_shards * 3);

            // Test recovery using first num_data_shards shards
            let test_shards: Vec<_> = shards[0..num_data_shards].to_vec();
            let test_indexes: Vec<_> = (0..num_data_shards).collect();

            let decoded = do_decode(test_shards, test_indexes, data_size, num_data_shards)?;
            assert_eq!(
                decoded, original_data,
                "Round trip failed for {}",
                description
            );

            // Also test with recovery shards to ensure padding works with Reed-Solomon
            if num_data_shards >= 2 {
                let recovery_shards: Vec<_> =
                    shards[num_data_shards..(num_data_shards * 2)].to_vec();
                let recovery_indexes: Vec<_> = (num_data_shards..(num_data_shards * 2)).collect();

                let decoded_from_recovery = do_decode(
                    recovery_shards,
                    recovery_indexes,
                    data_size,
                    num_data_shards,
                )?;
                assert_eq!(
                    decoded_from_recovery, original_data,
                    "Recovery failed for {}",
                    description
                );
            }
        }
        Ok(())
    }
}
