#[cfg(test)]
mod tests {
    use pvm::vm::dispatchers::two_immediates::dispatch_two_immediates;
    use pvm::vm::instructions::opcodes::*;
    use pvm::vm::test_builder::{VmTestBuilder, TEST_ADDR};
    use pvm::vm::InstructionResult;

    #[test]
    fn test_store_imm_u8_basic() {
        let mut program = vec![STORE_IMM_U8, 4];
        program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
        program.push(42);

        let mut vm = VmTestBuilder::new(program, &[0b1]).build();

        let result = dispatch_two_immediates(STORE_IMM_U8, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm
            .memory
            .as_ref()
            .unwrap()
            .read(TEST_ADDR as usize, 1)
            .unwrap();
        assert_eq!(memory_data[0], 42);
    }

    #[test]
    fn test_store_imm_u16_basic() {
        let mut program = vec![
            STORE_IMM_U16,
            4, // l_x = 4
        ];
        program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
        program.extend_from_slice(&[0x34, 0x12]);

        let mut vm = VmTestBuilder::new(program, &[0b1]).build();

        let result = dispatch_two_immediates(STORE_IMM_U16, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm
            .memory
            .as_ref()
            .unwrap()
            .read(TEST_ADDR as usize, 2)
            .unwrap();
        assert_eq!(memory_data, &[0x34, 0x12]);
    }

    #[test]
    fn test_store_imm_u32_basic() {
        let mut program = vec![STORE_IMM_U32, 4];
        program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
        program.extend_from_slice(&[0x78, 0x56, 0x34, 0x12]);

        let mut vm = VmTestBuilder::new(program, &[0b1, 0b100]).build();

        let result = dispatch_two_immediates(STORE_IMM_U32, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm
            .memory
            .as_ref()
            .unwrap()
            .read(TEST_ADDR as usize, 8)
            .unwrap();
        assert_eq!(memory_data, &[0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0]);
    }

    #[test]
    fn test_store_imm_u64_basic() {
        let mut program = vec![STORE_IMM_U64, 4];
        program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
        program.extend_from_slice(&[0x78, 0x56, 0x34, 0x12]);

        let mut vm = VmTestBuilder::new(program, &[0b1, 0b10000]).build();

        let result = dispatch_two_immediates(STORE_IMM_U64, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm
            .memory
            .as_ref()
            .unwrap()
            .read(TEST_ADDR as usize, 8)
            .unwrap();
        assert_eq!(memory_data, &[0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0]);
    }

    #[test]
    fn test_store_imm_u8_with_overflow() {
        let addr = 0x10001;

        let mut program = vec![STORE_IMM_U8, 4];

        program.extend_from_slice(&(addr as u32).to_le_bytes());
        program.extend_from_slice(&[0x44, 0x01]); // value = 0x0144, should become 0x44

        let mut vm = VmTestBuilder::new(program, &[0b1]).build();

        let result = dispatch_two_immediates(STORE_IMM_U8, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm.memory.as_ref().unwrap().read(addr as usize, 1).unwrap();
        assert_eq!(memory_data[0], 0x44);
    }

    #[test]
    fn test_store_imm_u16_with_overflow() {
        // Test that values > 65535 are properly modded
        let mut program = vec![
            STORE_IMM_U16,
            4, // l_x = 4
        ];
        program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes()); // 4-byte address
        program.extend_from_slice(&[0x00, 0x00, 0x01]); // value = 0x010000 = 65536, should become 0

        let mut vm = VmTestBuilder::new(program, &[0b1]).build();

        let result = dispatch_two_immediates(STORE_IMM_U16, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm
            .memory
            .as_ref()
            .unwrap()
            .read(TEST_ADDR as usize, 2)
            .unwrap();
        assert_eq!(memory_data, &[0x00, 0x00]); // 65536 % 65536 = 0
    }

    #[test]
    fn test_parameter_extraction_with_different_length_address() {
        let test_addr_2byte = 0x20000u32;
        let mut program = vec![
            STORE_IMM_U8,
            3, // l_x = 3 (3-byte address)
        ];
        program.extend_from_slice(&(test_addr_2byte).to_le_bytes()[0..3]); // 3-byte address
        program.push(0x99); // value

        let mut vm = VmTestBuilder::new(program, &[0b1]).build();

        let result = dispatch_two_immediates(STORE_IMM_U8, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm
            .memory
            .as_ref()
            .unwrap()
            .read(test_addr_2byte as usize, 1)
            .unwrap();
        assert_eq!(memory_data[0], 0x99);
    }

    #[test]
    fn test_parameter_extraction_with_large_first_byte() {
        // Test when first_byte % 8 > 4, should be clamped to 4
        let mut program = vec![
            STORE_IMM_U8,
            13, // 13 % 8 = 5, but min(5, 4) = 4, so l_x = 4
        ];
        program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes()); // 4-byte address
        program.push(0xAA); // value

        let mut vm = VmTestBuilder::new(program, &[0b1]).build();

        let result = dispatch_two_immediates(STORE_IMM_U8, &mut vm);

        assert_eq!(result, InstructionResult::Continue);
        let memory_data = vm
            .memory
            .as_ref()
            .unwrap()
            .read(TEST_ADDR as usize, 1)
            .unwrap();
        assert_eq!(memory_data[0], 0xAA);
    }

    #[test]
    fn test_unknown_opcode_returns_panic() {
        let mut vm = VmTestBuilder::new(vec![200, 1, 0x10, 0x42], &[0b10001]).build();

        let result = dispatch_two_immediates(200, &mut vm);

        assert_eq!(result, InstructionResult::Panic);
    }

    #[test]
    fn test_memory_fault_at_min_addr_boundary() {
        // Test writing to address just below MIN_ADDR
        let bad_addr = 0xFFFFu32; // Just below MIN_ADDR = 0x10000
        let mut program = vec![
            STORE_IMM_U8,
            3, // l_x = 3
        ];
        program.extend_from_slice(&(bad_addr).to_le_bytes()[0..3]); // 3-byte address
        program.push(0x42); // value

        let mut vm = VmTestBuilder::new(program, &[0b1]).build();

        let result = dispatch_two_immediates(STORE_IMM_U8, &mut vm);

        assert_eq!(result, InstructionResult::Panic); // Should panic due to MIN_ADDR check
    }
}
