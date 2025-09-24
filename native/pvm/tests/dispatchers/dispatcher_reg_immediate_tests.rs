#[cfg(test)]
mod tests {
    use pvm::core::Registers;
    use pvm::vm::dispatchers::reg_immediate::dispatch_reg_immediate;
    use pvm::vm::instructions::opcodes::*;
    use pvm::vm::test_builder::VmTestBuilder;
    use pvm::vm::test_builder::TEST_ADDR;
    use pvm::vm::InstructionResult;

    mod load_operations {
        use super::*;
        use pvm::core::consts::PAGE_SIZE;
        use pvm::core::{Memory, Permission};

        #[test]
        fn test_load_imm_loads_immediate_value() {
            let mut vm = VmTestBuilder::new(vec![LOAD_IMM, 1, 42], &[0b1]).build();

            let result = dispatch_reg_immediate(LOAD_IMM, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(1), 42);
        }

        #[test]
        fn test_load_imm_handles_multi_byte_immediate() {
            let mut vm =
                VmTestBuilder::new(vec![LOAD_IMM, 0x21, 0x78, 0x56, 0x34, 0x12], &[0b1]).build();

            let result = dispatch_reg_immediate(LOAD_IMM, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(1), 0x12345678);
        }

        #[test]
        fn test_load_imm_64_loads_64bit_immediate() {
            let mut vm = VmTestBuilder::new(
                vec![
                    LOAD_IMM_64,
                    0x01,
                    0x78,
                    0x56,
                    0x34,
                    0x12,
                    0xFC,
                    0xDE,
                    0xBA,
                    0x98,
                ],
                &[0b1, 0b100],
            )
            .build();

            let result = dispatch_reg_immediate(LOAD_IMM_64, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(1), 0x98BADEFC12345678);
        }

        #[test]
        fn test_load_imm_64_caps_register_index_to_12() {
            let mut vm = VmTestBuilder::new(
                vec![
                    LOAD_IMM_64,
                    15,
                    0x78,
                    0x56,
                    0x34,
                    0x12,
                    0xFC,
                    0xDE,
                    0xBA,
                    0x98,
                ],
                &[0b1],
            )
            .build();

            let result = dispatch_reg_immediate(LOAD_IMM_64, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(12), 0x98BADEFC12345678);
        }

        #[test]
        fn test_load_u8_reads_unsigned_byte() {
            let mut program = vec![LOAD_U8, 0x4];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut vm = VmTestBuilder::new(program, &[0b1]).build();

            // Write test data to memory
            vm.memory
                .as_mut()
                .unwrap()
                .write(TEST_ADDR as usize, &[42])
                .unwrap();

            let result = dispatch_reg_immediate(LOAD_U8, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(4), 42);
        }

        #[test]
        fn test_load_i8_reads_signed_byte() {
            let mut program = vec![LOAD_I8, 11];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut vm = VmTestBuilder::new(program, &[0b1]).build();

            // Write 0xFF (255 unsigned, -1 signed) to memory
            vm.memory
                .as_mut()
                .unwrap()
                .write(TEST_ADDR as usize, &[0xFF])
                .unwrap();

            let result = dispatch_reg_immediate(LOAD_I8, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(11), 0xFFFFFFFFFFFFFFFF); // Sign extended -1
        }

        #[test]
        fn test_load_u16_reads_unsigned_16bit() {
            let mut program = vec![LOAD_U16, 12];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut vm = VmTestBuilder::new(program, &[0b1]).build();

            // Write little-endian 16-bit value
            vm.memory
                .as_mut()
                .unwrap()
                .write(TEST_ADDR as usize, &[0x34, 0x12])
                .unwrap();

            let result = dispatch_reg_immediate(LOAD_U16, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(12), 0x1234);
        }

        #[test]
        fn test_load_i16_reads_signed_16bit() {
            let mut program = vec![LOAD_I16, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut vm = VmTestBuilder::new(program, &[0b1]).build();

            // Write 0xFFFF (-1 in signed 16-bit)
            vm.memory
                .as_mut()
                .unwrap()
                .write(TEST_ADDR as usize, &[0xFF, 0xFF])
                .unwrap();

            let result = dispatch_reg_immediate(LOAD_I16, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(1), 0xFFFFFFFFFFFFFFFF); // Sign extended -1
        }

        #[test]
        fn test_load_u32_reads_unsigned_32bit() {
            let mut program = vec![LOAD_U32, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut vm = VmTestBuilder::new(program, &[0b1]).build();

            // Write little-endian 32-bit value
            vm.memory
                .as_mut()
                .unwrap()
                .write(TEST_ADDR as usize, &[0x78, 0x56, 0x34, 0x12])
                .unwrap();

            let result = dispatch_reg_immediate(LOAD_U32, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(1), 0x12345678);
        }

        #[test]
        fn test_load_i32_reads_signed_32bit() {
            let mut program = vec![LOAD_I32, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut vm = VmTestBuilder::new(program, &[0b1]).build();

            // Write 0xFFFFFFFF (-1 in signed 32-bit)
            vm.memory
                .as_mut()
                .unwrap()
                .write(TEST_ADDR as usize, &[0xFF, 0xFF, 0xFF, 0xFF])
                .unwrap();

            let result = dispatch_reg_immediate(LOAD_I32, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(1), 0xFFFFFFFFFFFFFFFF); // Sign extended -1
        }

        #[test]
        fn test_load_u64_reads_unsigned_64bit() {
            let mut program = vec![LOAD_U64, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut vm = VmTestBuilder::new(program, &[0b1]).build();

            // Write little-endian 64-bit value
            vm.memory
                .as_mut()
                .unwrap()
                .write(
                    TEST_ADDR as usize,
                    &[0x78, 0x56, 0x34, 0x12, 0xFC, 0xDE, 0xBA, 0x98],
                )
                .unwrap();

            let result = dispatch_reg_immediate(LOAD_U64, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(1), 0x98BADEFC12345678);
        }

        #[test]
        fn test_load_operations_handle_memory_panic() {
            let mut vm =
                VmTestBuilder::new(vec![LOAD_U8, 0x01, 0x00, 0x10, 0x00, 0x00], &[0b1]).build(); // Address 0x1000 (below MIN_ADDR)

            let result = dispatch_reg_immediate(LOAD_U8, &mut vm);

            assert_eq!(result, InstructionResult::Panic);
        }

        #[test]
        fn test_load_u8_page_fault() {
            let mut memory = Memory::test_memory(32);
            // Set page 1 (address 0x10000-0x10FFF) to no permissions
            memory.set_access(0x10000, 1024, Permission::None);

            // Test address 0x10500 (middle of page 1)
            let mut vm = VmTestBuilder::new(vec![LOAD_U8, 0x01, 0x00, 0x05, 0x01, 0x00], &[0b1])
                .with_memory(memory)
                .build();

            let result = dispatch_reg_immediate(LOAD_U8, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x10000 });
        }

        #[test]
        fn test_load_i8_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x15000, 1, Permission::None);

            // Test address 0x15750 (random within page 2)
            let mut vm = VmTestBuilder::new(vec![LOAD_I8, 0x01, 0x50, 0x57, 0x01, 0x00], &[0b1])
                .with_memory(memory)
                .build();

            let result = dispatch_reg_immediate(LOAD_I8, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x15000 });
        }

        #[test]
        fn test_load_u16_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x1F000, PAGE_SIZE, Permission::None);

            // Test address 0x1FABC (random within page 3)
            let mut vm = VmTestBuilder::new(vec![LOAD_U16, 0x02, 0xBC, 0xFA, 0x01, 0x00], &[0b1])
                .with_memory(memory)
                .build();

            let result = dispatch_reg_immediate(LOAD_U16, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x1F000 });
        }

        #[test]
        fn test_load_i16_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x16000, 32, Permission::None);

            // Test address 0x40DEF (random within page 4)
            let mut vm = VmTestBuilder::new(vec![LOAD_I16, 0x01, 0xEF, 0x0D, 0x04, 0x00], &[0b1])
                .with_memory(memory)
                .build();

            let result = dispatch_reg_immediate(LOAD_I16, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x40000 });
        }

        #[test]
        fn test_load_u32_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x17000, 1, Permission::None);

            // Test address 0x17123 (random within page 5)
            let mut vm = VmTestBuilder::new(vec![LOAD_U32, 0x01, 0x23, 0x71, 0x01, 0x00], &[0b1])
                .with_memory(memory)
                .build();

            let result = dispatch_reg_immediate(LOAD_U32, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x17000 });
        }

        #[test]
        fn test_load_i32_page_fault() {
            let mut memory = Memory::test_memory(32);
            // length 0 should keep the page accessible
            memory.set_access(0x18000, 0, Permission::None);

            // Test address 0x18FED (random within page 6)
            let mut vm = VmTestBuilder::new(vec![LOAD_I32, 0x01, 0xED, 0x8F, 0x01, 0x00], &[0b1])
                .with_memory(memory)
                .build();

            let result = dispatch_reg_immediate(LOAD_I32, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
        }

        #[test]
        fn test_load_u64_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x10000, 1, Permission::None);
            // Test address 0x10FFF(random within page 6)

            let mut vm = VmTestBuilder::new(vec![LOAD_U64, 0x01, 0xFF, 0x0F, 0x01, 0x00], &[0b1])
                .with_memory(memory)
                .build();

            let result = dispatch_reg_immediate(LOAD_U64, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x10000 });
        }

        #[test]
        fn test_load_operations_cap_register_index() {
            let mut vm =
                VmTestBuilder::new(vec![LOAD_IMM, 0x5F, 42, 0x00, 0x00, 0x00], &[0b1]).build(); // Register 15 (0x5F & 0x0F = 15)

            let result = dispatch_reg_immediate(LOAD_IMM, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(12), 42); // Should be capped to register 12
        }
    }

    mod store_operations {
        use super::*;

        #[test]
        fn test_store_u8_writes_byte_from_register() {
            let mut program = vec![STORE_U8, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut registers = Registers::new();
            registers.set(1, 42);
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U8, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            let data = vm
                .memory
                .as_ref()
                .unwrap()
                .read(TEST_ADDR as usize, 1)
                .unwrap();
            assert_eq!(data[0], 42);
        }

        #[test]
        fn test_store_u8_masks_value_to_8_bits() {
            let mut program = vec![STORE_U8, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut registers = Registers::new();
            registers.set(1, 0x1234); // Should be masked to 0x34
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U8, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            let data = vm
                .memory
                .as_ref()
                .unwrap()
                .read(TEST_ADDR as usize, 1)
                .unwrap();
            assert_eq!(data[0], 0x34);
        }

        #[test]
        fn test_store_u16_writes_16bit_from_register() {
            let mut program = vec![STORE_U16, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut registers = Registers::new();
            registers.set(1, 0x1234);
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U16, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            let data = vm
                .memory
                .as_ref()
                .unwrap()
                .read(TEST_ADDR as usize, 2)
                .unwrap();
            assert_eq!(data, &[0x34, 0x12]); // Little-endian
        }

        #[test]
        fn test_store_u16_masks_value_to_16_bits() {
            let mut program = vec![STORE_U16, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut registers = Registers::new();
            registers.set(1, 0x12345678); // Should be masked to 0x5678
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U16, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            let data = vm
                .memory
                .as_ref()
                .unwrap()
                .read(TEST_ADDR as usize, 2)
                .unwrap();
            assert_eq!(data, &[0x78, 0x56]); // Little-endian
        }

        #[test]
        fn test_store_u32_writes_32bit_from_register() {
            let mut program = vec![STORE_U32, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());

            let mut registers = Registers::new();
            registers.set(1, 0x12345678);
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U32, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            let data = vm
                .memory
                .as_ref()
                .unwrap()
                .read(TEST_ADDR as usize, 4)
                .unwrap();
            assert_eq!(data, &[0x78, 0x56, 0x34, 0x12]); // Little-endian
        }

        #[test]
        fn test_store_u32_masks_value_to_32_bits() {
            let mut program = vec![STORE_U32, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());

            let mut registers = Registers::new();
            registers.set(1, 0x123456789ABCDEF0); // Should be masked to 0x9ABCDEF0
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U32, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            let data = vm
                .memory
                .as_ref()
                .unwrap()
                .read(TEST_ADDR as usize, 4)
                .unwrap();
            assert_eq!(data, &[0xF0, 0xDE, 0xBC, 0x9A]); // Little-endian
        }

        #[test]
        fn test_store_u64_writes_64bit_from_register() {
            let mut program = vec![STORE_U64, 0x01];
            program.extend_from_slice(&(TEST_ADDR as u32).to_le_bytes());
            let mut registers = Registers::new();
            registers.set(1, 0x123456789ABCDEF0);
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U64, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            let data = vm
                .memory
                .as_ref()
                .unwrap()
                .read(TEST_ADDR as usize, 8)
                .unwrap();
            assert_eq!(data, &[0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12]);
            // Little-endian
        }

        #[test]
        fn test_store_operations_handle_memory_fault() {
            let program = vec![STORE_U8, 0x01, 0x00, 0x10, 0x00, 0x00]; // Address 0x1000 (below MIN_ADDR)
            let mut registers = Registers::new();
            registers.set(1, 42);
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(STORE_U8, &mut vm);

            assert_eq!(result, InstructionResult::Panic);
        }
    }

    mod jump_operations {
        use super::*;

        #[test]
        fn test_jump_ind_successful_jump_to_valid_address() {
            // Create program with jump_ind at offset 0 and target instruction at offset 10
            let mut program = vec![JUMP_IND, 0x01, 0x00, 0x00, 0x00, 0x00];
            program.extend_from_slice(&[0; 4]); // Padding to reach offset 10
            program.push(FALLTHROUGH); // Target instruction at offset 10

            let mut registers = Registers::new();
            registers.set(1, 10); // Jump to offset 10
            let jump_table = vec![2, 4, 6, 8, 10];

            let mut vm = VmTestBuilder::new(program, &[0b1, 0b100])
                .with_registers(registers)
                .with_jump_table(jump_table)
                .build();

            let result = dispatch_reg_immediate(JUMP_IND, &mut vm);

            assert_eq!(result, InstructionResult::Jump(10));
        }

        #[test]
        fn test_jump_ind_handles_special_halt_address() {
            let program = vec![JUMP_IND, 0x01, 0x00, 0x00, 0x00, 0x00];
            let mut registers = Registers::new();
            registers.set(1, 0xFFFF0000); // Special halt address
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(JUMP_IND, &mut vm);

            assert_eq!(result, InstructionResult::Halt);
        }

        #[test]
        fn test_jump_ind_panics_on_unaligned_address() {
            let program = vec![JUMP_IND, 0x01, 0x00, 0x00, 0x00, 0x00];
            let mut registers = Registers::new();
            registers.set(1, 3); // Unaligned address (not divisible by 2)
            let mut vm = VmTestBuilder::new(program, &[0b1])
                .with_registers(registers)
                .build();

            let result = dispatch_reg_immediate(JUMP_IND, &mut vm);

            assert_eq!(result, InstructionResult::Panic);
        }

        #[test]
        fn test_jump_ind_panics_on_jump_to_non_instruction_start() {
            let program = vec![
                JUMP_IND,
                0x01,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                FALLTHROUGH,
            ];
            let mut registers = Registers::new();
            registers.set(1, 8);
            let jump_table = vec![2, 4, 6, 8, 10];
            let mut vm = VmTestBuilder::new(program, &[0b1, 0b10])
                .with_registers(registers)
                .with_jump_table(jump_table)
                .build();

            let result = dispatch_reg_immediate(JUMP_IND, &mut vm);

            assert_eq!(result, InstructionResult::Panic);
        }
    }
}
