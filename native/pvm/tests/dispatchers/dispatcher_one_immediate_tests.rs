#[cfg(test)]
mod tests {
    use pvm::core::{BitMask, Program, Registers, StartSet};
    use pvm::vm::dispatchers::one_immediate::dispatch_one_immediate;
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

    #[test]
    fn test_ecalli_sets_ecall_exit_status_with_immediate_value() {
        let program = Program::from_vec(vec![ECALLI, 42]);
        let bitmask = BitMask::from_bytes(&[0b101], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_one_immediate(ECALLI, &context, &mut state);

        assert_eq!(result, InstructionResult::Ecall { call_id: 42 });
    }

    #[test]
    fn test_ecalli_handles_multi_byte_immediate() {
        let program = Program::from_vec(vec![ECALLI, 0x78, 0x56, 0x34, 0x12]);
        let bitmask = BitMask::from_bytes(&[0b100001], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_one_immediate(ECALLI, &context, &mut state);

        assert_eq!(
            result,
            InstructionResult::Ecall {
                call_id: 0x12345678
            }
        );
    }

    #[test]
    fn test_jump_jumps_forward_to_valid_target() {
        let program = Program::from_vec(vec![JUMP, 3, 0, FALLTHROUGH]);
        let bitmask = BitMask::from_bytes(&[0b1001], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_one_immediate(JUMP, &context, &mut state);

        // Should jump to position 3 (pc=0 + offset=3)
        assert_eq!(result, InstructionResult::Jump(3));
    }

    #[test]
    fn test_jump_jumps_backward_to_valid_target() {
        let program = Program::from_vec(vec![FALLTHROUGH, JUMP, 255]);
        let bitmask = BitMask::from_bytes(&[0b1011], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(1); // Start at position 1 (jump instruction)

        let result = dispatch_one_immediate(JUMP, &context, &mut state);

        // Should jump backward to position 0 (pc=1 + shift=-1)
        assert_eq!(result, InstructionResult::Jump(0));
    }

    #[test]
    fn test_jump_panics_on_invalid_target() {
        let program = Program::from_vec(vec![JUMP, 1]);
        let bitmask = BitMask::from_bytes(&[0b101], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_one_immediate(JUMP, &context, &mut state);

        // Should panic because target position 1 is not in start_set
        assert_eq!(result, InstructionResult::Panic);
    }

    #[test]
    fn test_unknown_opcode_returns_panic() {
        let program = Program::from_vec(vec![200]); // Invalid opcode (not in one_immediate category)
        let bitmask = BitMask::from_bytes(&[0b101], program.len());
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);

        let result = dispatch_one_immediate(200, &context, &mut state);

        assert_eq!(result, InstructionResult::Panic);
    }

    #[test]
    fn test_ecalli_with_different_immediate_sizes() {
        // Test 1-byte immediate
        let program = Program::from_vec(vec![ECALLI, 0x42]);
        let bitmask = BitMask::from_bytes(&[0b101], program.len()); // skip 0 = read 1 byte
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);
        let result = dispatch_one_immediate(ECALLI, &context, &mut state);
        assert_eq!(result, InstructionResult::Ecall { call_id: 0x42 });

        // Test 2-byte immediate
        let program = Program::from_vec(vec![ECALLI, 0x34, 0x12]);
        let bitmask = BitMask::from_bytes(&[0b1001], program.len()); // skip 1 = read 2 bytes
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);
        let result = dispatch_one_immediate(ECALLI, &context, &mut state);
        assert_eq!(result, InstructionResult::Ecall { call_id: 0x1234 });

        // Test 3-byte immediate
        let program = Program::from_vec(vec![ECALLI, 0x56, 0x34, 0x12]);
        let bitmask = BitMask::from_bytes(&[0b10001], program.len()); // skip 2 = read 3 bytes
        let context = create_test_context(program, bitmask);
        let mut state = create_test_state(0);
        let result = dispatch_one_immediate(ECALLI, &context, &mut state);
        assert_eq!(result, InstructionResult::Ecall { call_id: 0x123456 });
    }
}
