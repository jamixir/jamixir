use crate::vm::instructions::opcodes::*;
use crate::vm::utils::decode_and_extend;
use crate::vm::{masks, InstructionResult, Vm, VmContext, VmState};

#[inline(always)]
pub fn dispatch_reg_two_imm(opcode: u8, vm: &mut Vm) -> InstructionResult {
    let (target_addr, v_y) = get_reg_two_imm_params(&vm.context, &vm.state, vm.state.pc);

    match opcode {
        STORE_IMM_IND_U8 => {
            let stored_value = v_y & masks::U8;
            let data = &[stored_value as u8];
            vm.write_memory(target_addr as usize, data)
        }
        STORE_IMM_IND_U16 => {
            let stored_value = v_y & masks::U16;
            let data = &(stored_value as u16).to_le_bytes()[..2];
            vm.write_memory(target_addr as usize, data)
        }
        STORE_IMM_IND_U32 => {
            let stored_value = v_y & masks::U32;
            let data = &(stored_value as u32).to_le_bytes()[..4];
            vm.write_memory(target_addr as usize, data)
        }
        STORE_IMM_IND_U64 => {
            let data = &v_y.to_le_bytes()[..8];
            vm.write_memory(target_addr as usize, data)
        }

        _ => InstructionResult::Panic,
    }
}

#[inline(always)]
fn get_reg_two_imm_params(context: &VmContext, state: &VmState, pc: usize) -> (u64, u64) {
    let program = &context.program;
    let bitmask = &context.bitmask;

    let register_index = (program[pc + 1] & 0x0F).min(12) as usize;
    let l_x = (((program[pc + 1] as i8) >> 4) & 7).min(4) as usize;

    let l_y = (bitmask.skip(pc).saturating_sub(l_x).saturating_sub(1)).min(4);

    let v_x = decode_and_extend(program, pc + 2, l_x);
    let v_y = decode_and_extend(program, pc + 2 + l_x, l_y);
    let w_a = state.registers.get(register_index);
    let target_addr = w_a.wrapping_add(v_x);

    (target_addr, v_y)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_reg_two_imm(&mut self, opcode: u8) -> InstructionResult {
        dispatch_reg_two_imm(opcode, self)
    }
}
