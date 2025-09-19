#[cfg(test)]
mod tests {
    use pvm::core::{BitMask, Program, Registers, StartSet};
    use pvm::vm::dispatchers::reg_imm_offset::dispatch_reg_immediate_offset;
    use pvm::vm::instructions::opcodes::*;
    use pvm::vm::{InstructionResult, VmContext, VmState};

    fn create_test_context(program: Program, bitmask: BitMask) -> VmContext {
        let start_set = StartSet::build(&program, &bitmask);
        VmContext {
            program,
            bitmask,
            jump_table: vec![],
            start_set,
        }
    }

    fn create_test_state(pc: usize) -> VmState {
        VmState::new(Registers::new(), pc, 1000)
    }

    fn create_test_state_with_registers(pc: usize, registers: Registers) -> VmState {
        VmState::new(registers, pc, 1000)
    }

    #[test]
    fn test_load_imm_jump_loads_immediate_value_and_jumps() {
        // Program: load_imm_jump r1, 42, target=10
        // 0x11 = register 1, immediate length 1
        let program = Program::from_vec(vec![LOAD_IMM_JUMP, 0x11, 42, 4]);
        // Bitmask: 8 = skip 3 bytes (1 for opcode + 1 for params + 1 for immediate + 1 for offset)
        let bitmask = BitMask::from_bytes(&[0b0001], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_reg_immediate_offset(LOAD_IMM_JUMP, &context, &mut state);

        assert_eq!(state.registers.get(1), 42);
        assert_eq!(result, InstructionResult::Jump(4));
    }

    #[test]
    fn test_load_imm_jump_handles_invalid_jump_target() {
        // Jump target not marked as instruction start
        let program = Program::from_vec(vec![LOAD_IMM_JUMP, 0x11, 42, 10]);
        // Bitmask: 9 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b10001], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_reg_immediate_offset(LOAD_IMM_JUMP, &context, &mut state);

        assert_eq!(result, InstructionResult::Panic);
    }

    #[test]
    fn test_branch_eq_imm_compares_equal_values() {
        let program = Program::from_vec(vec![
            BRANCH_EQ_IMM,
            0x11,
            42,
            9, // branch_eq_imm r1, 42, target=9
            STORE_IMM_U8,
            0x01,
            10,
            5, // store_imm_u8 r0, 10, 5
            FALLTHROUGH,
        ]);
        let bitmask = BitMask::from_bytes(&[0b00010001, 0b1], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 42);
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_EQ_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(9));
    }

    #[test]
    fn test_branch_ne_imm_compares_unequal_values() {
        let program = Program::from_vec(vec![
            BRANCH_NE_IMM,
            0x11,
            42,
            10, // branch_ne_imm r1, 42, target=10
            STORE_IMM_U8,
            0x01,
            10,
            5,    // store_imm_u8 r0, 10, 5
            TRAP, // trap
            FALLTHROUGH,
        ]);
        let bitmask = BitMask::from_bytes(&[0b00010001, 0b11], program.len());

        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 43); // Different value
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_NE_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(10));
    }

    #[test]
    fn test_branch_lt_u_imm_compares_unsigned_values() {
        let program = Program::from_vec(vec![BRANCH_LT_U_IMM, 0x11, 0xFF, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x7F); // 127 < 255
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_LT_U_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_branch_le_u_imm_handles_equal_values() {
        let program = Program::from_vec(vec![BRANCH_LE_U_IMM, 0x11, 0x80, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x80); // 128 == 128
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_LE_U_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_branch_ge_u_imm_handles_greater_values() {
        let program = Program::from_vec(vec![BRANCH_GE_U_IMM, 0x11, 0x7F, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x80); // 128 >= 127
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_GE_U_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_branch_gt_u_imm_handles_strictly_greater_values() {
        let program = Program::from_vec(vec![BRANCH_GT_U_IMM, 0x11, 0x7F, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x80); // 128 > 127
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_GT_U_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_branch_lt_s_imm_compares_signed_values() {
        let program = Program::from_vec(vec![BRANCH_LT_S_IMM, 0x11, 0x07, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x04); // 4 < 7
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_LT_S_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_branch_le_s_imm_handles_equal_signed_values() {
        let program = Program::from_vec(vec![BRANCH_LE_S_IMM, 0x11, 0x08, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x08); // 8 == 8
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_LE_S_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_branch_ge_s_imm_handles_greater_signed_values() {
        let program = Program::from_vec(vec![BRANCH_GE_S_IMM, 0x11, 0x0D, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x0F); // 15 >= 13
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_GE_S_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_branch_gt_s_imm_handles_strictly_greater_signed_values() {
        let program = Program::from_vec(vec![BRANCH_GT_S_IMM, 0x11, 0x0C, 5, FALLTHROUGH]);
        // Bitmask: 17 = skip 4 bytes
        let bitmask = BitMask::from_bytes(&[0b110001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x0D); // 13 > 12
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_GT_S_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(5));
    }

    #[test]
    fn test_handles_multi_byte_immediate_and_offset_values() {
        // Program: branch_eq_imm r1, 0x0FFF, target=0x05
        // 0x21 = register 1, immediate length 2
        let program = Program::from_vec(vec![
            BRANCH_EQ_IMM,
            0x21,
            0xFF,
            0x0F,
            0x05,
            0x00,
            FALLTHROUGH,
        ]);
        // Bitmask: 33 = skip 5 bytes
        let bitmask = BitMask::from_bytes(&[0b11100001], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(1, 0x0FFF);
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_EQ_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(0x05));
    }

    #[test]
    fn test_caps_register_index_to_12() {
        // Program: branch_eq_imm r12, 42, target=7
        // 0x5D = register 13 (capped to 12), immediate length 1
        let program = Program::from_vec(vec![
            BRANCH_EQ_IMM,
            0x5D,
            0x2A,
            0x00,
            0x00,
            0x00,
            7,
            FALLTHROUGH,
        ]);
        // Bitmask: 129 = skip 6 bytes
        let bitmask = BitMask::from_bytes(&[0b10000001, 0b1], program.len());
        let context = create_test_context(program, bitmask);
        let mut registers = Registers::new();
        registers.set(12, 42); // Register 12, not 13
        let mut state = create_test_state_with_registers(0, registers);

        let result = dispatch_reg_immediate_offset(BRANCH_EQ_IMM, &context, &mut state);

        assert_eq!(result, InstructionResult::Jump(7));
    }

    #[test]
    fn test_unknown_opcode_returns_panic() {
        let program = Program::from_vec(vec![200, 0, 0]); // Invalid opcode
        let bitmask = BitMask::from_bytes(&[0b001], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_reg_immediate_offset(200, &context, &mut state);

        assert_eq!(result, InstructionResult::Panic);
    }
}
