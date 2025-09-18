#[cfg(test)]
mod tests {
    use pvm::core::{BitMask, Program, StartSet};

    #[test]
    fn test_skip_basic_patterns() {
        let bitmask = BitMask::from_bytes(&[0b11], 1);
        let skip_distance = bitmask.skip(0);
        assert_eq!(skip_distance, 0);

        let bitmask = BitMask::from_bytes(&[0b1001], 3);
        assert_eq!(bitmask.skip(0), 2);

        let bitmask = BitMask::from_bytes(&[0b1, 0b1], 8);
        assert_eq!(bitmask.skip(0), 7);
    }

    #[test]
    fn test_skip_complex_instructions() {
        // Complex pattern: bit pattern 10010100 = 148
        // Bits 2, 4, 7 are set (positions 2, 4, 7 in little-endian)
        let bitmask = BitMask::from_bytes(&[0b0101_0001, 0b10], 9); // 0b10010100

        // From position 0, next instruction is at position 2 (skip 1)
        assert_eq!(bitmask.skip(0), 3);

        // From position 2, next instruction is at position 4 (skip 1)
        assert_eq!(bitmask.skip(4), 1);

        // From position 4, next instruction is at position 7 (skip 2)
        assert_eq!(bitmask.skip(6), 2);

        // From position 7, no more instructions
        assert_eq!(bitmask.skip(9), 0); // Trap instruction at position 10
    }

    #[test]
    fn test_skip_boundary_conditions() {
        // At end of bitmask - bit pattern: 10000000 = 128 (only bit 7 set)
        let bitmask = BitMask::from_bytes(&[0b10000000], 8); // 0b10000000, only bit 7 set
        assert_eq!(bitmask.skip(7), 0); // Next instruction is trap at position 8

        // Beyond bitmask length
        let bitmask = BitMask::from_bytes(&[0b1], 8); // 0b00000001
        assert_eq!(bitmask.skip(8), 0); // Trap instruction due to padding

        // Empty bitmask
        let bitmask = BitMask::from_bytes(&[], 0);
        assert_eq!(bitmask.skip(0), 0); // Trap instruction due to padding
    }

    #[test]
    fn test_build_start_set_simple_program() {
        // Program: [trap, fallthrough, store_imm_u8, imm1, imm2]
        let program = Program::from_vec(vec![0x00, 0x01, 0x3E, 0x01, 0x05]);
        // Bitmask with instructions at positions 0, 1, 2 (bits 0, 1, 2 set = 0b00000111 = 7)
        let bitmask = BitMask::from_bytes(&[7], program.len()); // 0b00000111

        let starts = StartSet::build(&program, &bitmask);

        // Should have start at position 0 (always)
        assert!(starts.includes(0));

        // After trap (0x00), should mark next instruction as start
        assert!(starts.includes(1));

        // After fallthrough (0x01), should mark next instruction as start
        assert!(starts.includes(2));
    }

    #[test]
    fn test_build_start_set_with_jumps_and_branches() {
        // Program: [jump, imm1, imm2, branch_eq, imm1, imm2]
        let program = Program::from_vec(vec![0x28, 0x01, 0x05, 0xAA, 0x01, 0x0A]); // 0x28=40=jump, 0xAA=170=branch_eq
                                                                                   // Instructions at positions 0 and 3 (bits 0 and 3 set = 0b00001001 = 9)
        let bitmask = BitMask::from_bytes(&[9], program.len()); // 0b00001001

        let starts = StartSet::build(&program, &bitmask);

        // Should have start at position 0 (always)
        assert!(starts.includes(0));

        // After jump, should mark next instruction as start
        assert!(starts.includes(3));

        // After branch_eq, should mark next instruction as start
        assert!(starts.includes(6));
    }

    #[test]
    fn test_build_start_set_no_termination_instructions() {
        // Program with only non-termination instruction: store_imm_u8
        let program = Program::from_vec(vec![0x3E, 0x01, 0x05]);
        let bitmask = BitMask::from_bytes(&[1], program.len()); // Only bit 0 set = 0b1

        let starts = StartSet::build(&program, &bitmask);

        // Should only have start at position 0
        assert!(starts.includes(0));

        // Should not have starts at other positions
        assert!(!starts.includes(1));
        assert!(!starts.includes(2));
    }

    #[test]
    fn test_build_start_set_multiple_termination_instructions() {
        // Program: [fallthrough, trap, jump, imm1, imm2]
        let program = Program::from_vec(vec![0x01, 0x00, 0x28, 0x01, 0x05]); // fallthrough, trap, jump
        let bitmask = BitMask::from_bytes(&[7], program.len()); // Bits 0, 1, 2 set = 0b00000111 = 7

        let starts = StartSet::build(&program, &bitmask);

        // Should have start at position 0 (always)
        assert!(starts.includes(0));

        // After fallthrough at pos 0, should mark pos 1 as start
        assert!(starts.includes(1));

        // After trap at pos 1, should mark pos 2 as start
        assert!(starts.includes(2));
    }
}
