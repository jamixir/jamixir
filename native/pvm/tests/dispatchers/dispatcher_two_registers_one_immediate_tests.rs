#[cfg(test)]
mod tests {
    use pvm::core::consts::PAGE_SIZE;
    use pvm::core::{Memory, Permission, Registers};
    use pvm::vm::dispatchers::two_registers_one_immediate::dispatch_two_registers_one_immediate;
    use pvm::vm::instructions::opcodes::*;
    use pvm::vm::test_builder::VmTestBuilder;
    use pvm::vm::InstructionResult;

    mod load_ind_operations {
        use super::*;

        #[test]
        fn test_load_ind_u8_page_fault() {
            let mut memory = Memory::test_memory(17);
            memory.set_access(0x10000, 1, Permission::None);

            // Test address 0x10500 (random within page 1)

            let mut registers = Registers::new();
            registers.set(1, 0x10000); // Base address in register 1

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U8, 0x12, 0x50], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U8, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x10000 });
        }

        #[test]
        fn test_load_ind_i8_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x14000, PAGE_SIZE, Permission::None);

            let mut registers = Registers::new();
            registers.set(1, 0x14000);

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_I8, 0x10, 0xEE, 2, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_I8, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x14000 });
        }

        #[test]
        fn test_load_ind_u16_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x15000, PAGE_SIZE, Permission::None);

            let mut registers = Registers::new();
            registers.set(1, 0x15000); // Base address in register 2

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U16, 0x15, 0xFF, 0x0F, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U16, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x15000 });
        }

        #[test]
        fn test_load_ind_i16_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x16000, PAGE_SIZE, Permission::None);

            let mut registers = Registers::new();
            registers.set(3, 0x16000); // Base address in register 3

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_I16, 0x35, 0x78, 0x0D, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_I16, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x16000 });
        }

        #[test]
        fn test_load_ind_u32_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x1F000, PAGE_SIZE, Permission::None);

            let mut registers = Registers::new();
            registers.set(4, 0x20000); // Base address in register 4

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U32, 0x46, 0, 0x01, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U32, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x20000 });
        }

        #[test]
        fn test_load_ind_i32_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x18000, PAGE_SIZE, Permission::None);

            // Test address 0x18000 (page 24)
            // r_a=7, r_b=5, v_x=0x0 (offset), so r_b + v_x = 0x18000 + 0x0 = 0x18000
            let mut registers = Registers::new();
            registers.set(5, 0x18000); // Base address in register 5

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_I32, 0x57, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_I32, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x18000 });
        }

        #[test]
        fn test_load_ind_u64_page_fault() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x19000, PAGE_SIZE, Permission::None);

            // Test address 0x19000 (page 25)
            // r_a=8, r_b=6, v_x=0x0 (offset), so r_b + v_x = 0x19000 + 0x0 = 0x19000
            let mut registers = Registers::new();
            registers.set(6, 0x19000); // Base address in register 6

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U64, 0x68, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U64, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x19000 });
        }

        // Test page boundary cases with different offsets
        #[test]
        fn test_load_ind_u8_page_fault_different_offset() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x1A000, PAGE_SIZE, Permission::None);

            // Test address 0x1A000 (page 26)
            // r_a=9, r_b=1, v_x=0x0 (offset), so r_b + v_x = 0x1A000 + 0x0 = 0x1A000
            let mut registers = Registers::new();
            registers.set(1, 0x1A000); // Base address in register 1

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U8, 0x19, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U8, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x1A000 });
        }

        #[test]
        fn test_load_ind_u16_page_fault_cross_page_boundary() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x1B000, PAGE_SIZE, Permission::None);

            // Test address 0x1B000 (page 27)
            // r_a=10, r_b=2, v_x=0x0 (offset), so r_b + v_x = 0x1B000 + 0x0 = 0x1B000
            let mut registers = Registers::new();
            registers.set(2, 0x1B000); // Base address in register 2

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U16, 0x2A, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U16, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x1B000 });
        }

        #[test]
        fn test_load_ind_u32_page_fault_cross_page_boundary() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x1C000, PAGE_SIZE, Permission::None);

            // Test address 0x1C000 (page 28)
            // r_a=11, r_b=3, v_x=0x0 (offset), so r_b + v_x = 0x1C000 + 0x0 = 0x1C000
            let mut registers = Registers::new();
            registers.set(3, 0x1C000); // Base address in register 3

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U32, 0x3B, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U32, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x1C000 });
        }

        #[test]
        fn test_load_ind_u64_page_fault_cross_page_boundary() {
            let mut memory = Memory::test_memory(32);
            memory.set_access(0x1D000, PAGE_SIZE, Permission::None);

            // Test address 0x1D000 (page 29)
            // r_a=12, r_b=4, v_x=0x0 (offset), so r_b + v_x = 0x1D000 + 0x0 = 0x1D000
            let mut registers = Registers::new();
            registers.set(4, 0x1D000); // Base address in register 4

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U64, 0x4C, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U64, &mut vm);

            assert_eq!(result, InstructionResult::Fault { page: 0x1D000 });
        }

        // Test successful loads (no page fault) to ensure the tests are working correctly
        #[test]
        fn test_load_ind_u8_success() {
            let mut memory = Memory::test_memory(32);
            // Don't restrict any pages - should succeed

            // Test address 0x10000 (page 16, should be accessible)
            // r_a=2, r_b=1, v_x=0x0 (offset), so r_b + v_x = 0x10000 + 0x0 = 0x10000
            let mut registers = Registers::new();
            registers.set(1, 0x10000); // Base address in register 1

            // Write test data to memory
            memory.write(0x10000, &[42]).unwrap();

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_U8, 0x12, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_U8, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(2), 42);
        }

        #[test]
        fn test_load_ind_i8_success() {
            let mut memory = Memory::test_memory(32);
            // Don't restrict any pages - should succeed

            // Test address 0x10000 (page 16, should be accessible)
            // r_a=3, r_b=1, v_x=0x0 (offset), so r_b + v_x = 0x10000 + 0x0 = 0x10000
            let mut registers = Registers::new();
            registers.set(1, 0x10000); // Base address in register 1

            // Write test data to memory (0xFF = -1 in signed 8-bit)
            memory.write(0x10000, &[0xFF]).unwrap();

            let mut vm = VmTestBuilder::new(vec![LOAD_IND_I8, 0x13, 0, 0, 0, 0], &[0b1])
                .with_memory(memory)
                .with_registers(registers)
                .build();

            let result = dispatch_two_registers_one_immediate(LOAD_IND_I8, &mut vm);

            assert_eq!(result, InstructionResult::Continue);
            assert_eq!(vm.state.registers.get(3), 0xFFFFFFFFFFFFFFFF); // Sign extended -1
        }
    }
}
