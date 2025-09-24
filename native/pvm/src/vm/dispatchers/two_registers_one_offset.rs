use crate::vm::instructions::opcodes::*;
use crate::vm::utils::{decode_bytes, unsigned_to_signed};
use crate::vm::{InstructionResult, Vm, VmContext, VmState};

#[inline(always)]
pub fn dispatch_two_registers_one_offset(
    opcode: u8,
    context: &VmContext,
    state: &mut VmState,
) -> InstructionResult {
    let (w_a, w_b, v_x) = get_two_registers_one_offset_params(context, state);

    match opcode {
        BRANCH_EQ => context.branch(v_x, w_a == w_b),
        BRANCH_NE => context.branch(v_x, w_a != w_b),
        BRANCH_LT_U => context.branch(v_x, w_a < w_b),
        BRANCH_LT_S => {
            let w_a_signed = unsigned_to_signed(w_a, 8);
            let w_b_signed = unsigned_to_signed(w_b, 8);
            context.branch(v_x, w_a_signed < w_b_signed)
        }
        BRANCH_GE_U => context.branch(v_x, w_a >= w_b),
        BRANCH_GE_S => {
            let w_a_signed = unsigned_to_signed(w_a, 8);
            let w_b_signed = unsigned_to_signed(w_b, 8);
            context.branch(v_x, w_a_signed >= w_b_signed)
        }
        _ => InstructionResult::Panic,
    }
}

// Formula (A.24) v0.7.0
#[inline(always)]
fn get_two_registers_one_offset_params(context: &VmContext, state: &VmState) -> (u64, u64, usize) {
    let program = &context.program;
    let bitmask = &context.bitmask;

    let pc = state.pc;
    let byte1 = program[pc + 1];
    let r_a = (byte1 & 15).min(12) as usize;
    let r_b = (byte1 >> 4).min(12) as usize;

    let l_x = (bitmask.skip(pc).saturating_sub(1)).min(4);
    let signed_immediate = unsigned_to_signed(decode_bytes(program, pc + 2, l_x), l_x);
    let v_x = ((pc as i64).wrapping_add(signed_immediate)) as usize;

    let w_a = state.registers.get(r_a);
    let w_b = state.registers.get(r_b);

    (w_a, w_b, v_x)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_two_registers_one_offset(&mut self, opcode: u8) -> InstructionResult {
        dispatch_two_registers_one_offset(opcode, &self.context, &mut self.state)
    }
}
