#[cfg(test)]
mod tests {
    use pvm::{
        core::{BitMask, Program},
        encoding::{deblob, encode_program},
    };

    fn encode_decode(
        program: &[u8],
        bitmask: &[u8],
        jump_table: &[usize],
        z: u64,
    ) -> (Program, BitMask, Vec<usize>) {
        let encoded = encode_program(program, bitmask, jump_table, z);
        let blob = deblob(&encoded);
        (blob.program, blob.bitmask, blob.jump_table)
    }

    #[test]
    fn test_empty_jump_table() {
        let program = &[60, 171, 142, 73, 61, 2, 3];
        let bitmask = &[137];
        let jump_table: &[usize] = &[];
        let z = 1;

        let (decoded_program, decoded_bitmask, decoded_jump_table) =
            encode_decode(program, bitmask, jump_table, z);

        assert_eq!(decoded_program.as_slice(), program);
        assert_eq!(decoded_jump_table, jump_table);
        assert_eq!(decoded_bitmask.size(), 1);
    }

    #[test]
    fn test_jump_table() {
        let program = &[1, 2, 3, 4];
        let bitmask = &[0xFF];
        let jump_table: &[usize] = &[10, 20, 30];
        let z = 1;

        let (decoded_program, decoded_bitmask, decoded_jump_table) =
            encode_decode(program, bitmask, jump_table, z);

        assert_eq!(decoded_program.as_slice(), program);
        assert_eq!(decoded_jump_table, jump_table);
        assert_eq!(decoded_bitmask.size(), 1);
    }

    #[test]
    fn test_larger_z() {
        let program = &[1, 2, 3, 4];
        let bitmask = &[0xFF];
        let jump_table: &[usize] = &[256, 512, 1024]; // requires 2 bytes each
        let z = 2;

        let (decoded_program, _decoded_bitmask, decoded_jump_table) =
            encode_decode(program, bitmask, jump_table, z);

        assert_eq!(decoded_program.as_slice(), program);
        assert_eq!(decoded_jump_table, jump_table);
    }

    #[test]
    fn test_max_jump_and_program() {
        let program = &[1u8; 100];
        let bitmask = &[0xAA, 0x55];
        let jump_table: &[usize] = &[0, 1, 2, 255, 1024];
        let z = 2;

        let (decoded_program, decoded_bitmask, decoded_jump_table) =
            encode_decode(program, bitmask, jump_table, z);

        assert_eq!(decoded_program.as_slice(), program);
        assert_eq!(decoded_jump_table, jump_table);
        assert_ne!(decoded_bitmask.size(), 0);
    }

    #[test]
    fn test_trap_bit_set() {
        let program = &[0x01, 0x02, 0x03];
        let bitmask = &[0b10100000]; // 1 byte
        let jump_table: &[usize] = &[];
        let z = 1;

        let (_decoded_program, decoded_bitmask, _decoded_jump_table) =
            encode_decode(program, bitmask, jump_table, z);

        // Trap bit is always added at program_len
        let trap_bit_pos = program.len();
        let word_index = trap_bit_pos / 64;
        let bit_index = trap_bit_pos % 64;
        assert_eq!(
            (decoded_bitmask.as_slice()[word_index] >> bit_index) & 1,
            1,
            "Trap bit not set correctly"
        );
    }
}

#[cfg(test)]
mod bitmask_skip_tests {
    use pvm::core::BitMask;

    fn compute_skips(bitmask: &BitMask) -> Vec<usize> {
        let mut skips = Vec::new();
        let mut pc = 0;

        loop {
            // Stop if we've gone beyond the program limit
            if pc >= bitmask.program_limit() {
                break;
            }

            let skip_distance = bitmask.skip(pc);
            skips.push(skip_distance);
            pc += skip_distance + 1;
        }

        skips
    }

    #[test]
    fn bitmask_packing_and_skip_consistency() {
        let bitmask_bytes = &[0b1010_0001, 0b0000_0100];
        let packed = BitMask::from_bytes(bitmask_bytes, 11);

        let expected_skips = vec![4, 1, 2, 0];

        let actual_skips = compute_skips(&packed);

        assert_eq!(
            expected_skips, actual_skips,
            "Packed bitmask skips mismatch"
        );
    }

    #[test]
    fn bitmask_with_trap_and_skips() {
        let bitmask_bytes = &[0b1010_1011, 0b0001_0000];
        let prog_len = 13; // cut program length to force trap in last bits
        let packed = BitMask::from_bytes(bitmask_bytes, prog_len);

        let actual_skips = compute_skips(&packed);

        let expected_skips = vec![0, 1, 1, 1, 4, 0];

        assert_eq!(
            expected_skips, actual_skips,
            "Skips including trap mismatch"
        );
    }

    #[test]
    fn concrete_single_u64_bitmask_examples() {
        // Example 1: Single u64 word (8 bytes)
        // Little-endian representation: 0x8101010101010101
        // Binary (LE): 0000_0001 0000_0001 0000_0001 0000_0001 0000_0001 0000_0001 0000_0001 1000_0001
        // Bit positions (0-indexed): 0, 8, 16, 24, 32, 40, 48, 56, 63
        // First bit is always 1 (program starts from instruction)
        let bitmask_bytes = &[0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x81]; // 8 bytes = 1 u64
        let prog_len = 60; // Program shorter than full bitmask
        let packed = BitMask::from_bytes(bitmask_bytes, prog_len);

        let expected_skips = vec![7, 7, 7, 7, 7, 7, 7, 3];
        let actual_skips = compute_skips(&packed);
        assert_eq!(expected_skips, actual_skips, "Single u64 skip mismatch");
    }

    #[test]
    fn concrete_trap_bit_effects() {
        let bitmask_bytes = &[0x05]; // Binary: 0000_0101 (bits 0 and 2 set)

        // Test 1:(trap at bit 3)
        let packed1 = BitMask::from_bytes(bitmask_bytes, 3);
        // Set bits: 0, 2, 3 (trap) -> skip distances: 1, 0
        let expected_skips1 = vec![1, 0];
        let actual_skips1 = compute_skips(&packed1);
        assert_eq!(expected_skips1, actual_skips1, "Short program trap effect");

        // Test 2:  (trap at bit 5)
        let packed2 = BitMask::from_bytes(bitmask_bytes, 5);
        // Set bits: 0, 2, 5 (trap) -> skip distances: 1, 2
        let expected_skips2 = vec![1, 2];
        let actual_skips2 = compute_skips(&packed2);
        assert_eq!(expected_skips2, actual_skips2, "Medium program trap effect");

        // Test 3: (trap at bit 10)
        let packed3 = BitMask::from_bytes(bitmask_bytes, 10);
        // Set bits: 0, 2, 10 (trap) -> skip distances: 1, 7
        let expected_skips3 = vec![1, 7];
        let actual_skips3 = compute_skips(&packed3);
        assert_eq!(expected_skips3, actual_skips3, "Long program trap effect");
    }
}
