use crate::vm::instructions::opcodes::*;
use crate::vm::utils::{decode_and_extend, decode_bytes, unsigned_to_signed};
use crate::vm::{InstructionResult, Vm, VmContext, VmState};

#[inline(always)]
pub fn dispatch_reg_immediate_offset(
    opcode: u8,
    context: &VmContext,
    state: &mut VmState,
) -> InstructionResult {
    let (r_a, v_x, v_y) = get_reg_imm_offset_params(context, state.pc);

    match opcode {
        LOAD_IMM_JUMP => {
            state.registers.set(r_a, v_x);
            context.branch(v_y, true)
        }
        BRANCH_EQ_IMM => {
            let w_a = state.registers.get(r_a);
            context.branch(v_y, w_a == v_x)
        }
        BRANCH_NE_IMM => {
            let w_a = state.registers.get(r_a);
            context.branch(v_y, w_a != v_x)
        }
        BRANCH_LT_U_IMM => {
            let w_a = state.registers.get(r_a);
            context.branch(v_y, w_a < v_x)
        }
        BRANCH_LE_U_IMM => {
            let w_a = state.registers.get(r_a);
            context.branch(v_y, w_a <= v_x)
        }
        BRANCH_GE_U_IMM => {
            let w_a = state.registers.get(r_a);
            context.branch(v_y, w_a >= v_x)
        }
        BRANCH_GT_U_IMM => {
            let w_a = state.registers.get(r_a);
            context.branch(v_y, w_a > v_x)
        }
        BRANCH_LT_S_IMM => {
            let w_a = state.registers.get(r_a);
            let w_a_signed = unsigned_to_signed(w_a, 8);
            let v_x_signed = unsigned_to_signed(v_x, 8);
            context.branch(v_y, w_a_signed < v_x_signed)
        }
        BRANCH_LE_S_IMM => {
            let w_a = state.registers.get(r_a);
            let w_a_signed = unsigned_to_signed(w_a, 8);
            let v_x_signed = unsigned_to_signed(v_x, 8);
            context.branch(v_y, w_a_signed <= v_x_signed)
        }
        BRANCH_GE_S_IMM => {
            let w_a = state.registers.get(r_a);
            let w_a_signed = unsigned_to_signed(w_a, 8);
            let v_x_signed = unsigned_to_signed(v_x, 8);
            context.branch(v_y, w_a_signed >= v_x_signed)
        }
        BRANCH_GT_S_IMM => {
            let w_a = state.registers.get(r_a);
            let w_a_signed = unsigned_to_signed(w_a, 8);
            let v_x_signed = unsigned_to_signed(v_x, 8);
            context.branch(v_y, w_a_signed > v_x_signed)
        }
        _ => InstructionResult::Panic,
    }
}

#[inline(always)]
fn get_reg_imm_offset_params(context: &VmContext, pc: usize) -> (usize, u64, usize) {
    let program = &context.program;
    let bitmask = &context.bitmask;

    let first_byte = program[pc + 1];

    //  first_byte % 16, clamped to max 12
    let r_a = (first_byte & 0x0F).min(12) as usize;

    // (first_byte / 16) % 8, clamped to max 4
    let l_x = ((first_byte >> 4) & 0x07).min(4) as usize;

    let skip_value = bitmask.skip(pc);
    let l_y = (skip_value.saturating_sub(l_x).saturating_sub(1)).min(4) as usize;

    let v_x = decode_and_extend(program, pc + 2, l_x);

    let offset_bytes = decode_bytes(program, pc + 2 + l_x, l_y);
    let offset_signed = unsigned_to_signed(offset_bytes, l_y);
    let v_y = (pc as i64).wrapping_add(offset_signed) as usize;

    (r_a, v_x, v_y)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_reg_immediate_offset(&mut self, opcode: u8) -> InstructionResult {
        dispatch_reg_immediate_offset(opcode, &self.context, &mut self.state)
    }
}
