use crate::vm::instructions::opcodes::*;
use crate::vm::utils::decode_and_extend;
use crate::vm::{masks, InstructionResult, Vm};

#[inline(always)]
pub fn dispatch_two_immediates(opcode: u8, vm: &mut Vm) -> InstructionResult {
    let (v_x, v_y) = get_two_immediates_params(vm);

    match opcode {
        STORE_IMM_U8 => {
            let value = v_y & masks::U8;
            let data = &[value as u8];
            vm.write_memory(v_x as usize, data)
        }
        STORE_IMM_U16 => {
            let value = v_y & masks::U16;
            let data = &(value as u16).to_le_bytes()[..2];
            vm.write_memory(v_x as usize, data)
        }
        STORE_IMM_U32 => {
            let value = v_y & masks::U32;
            let data = &(value as u32).to_le_bytes()[..4];
            vm.write_memory(v_x as usize, data)
        }
        STORE_IMM_U64 => {
            let data = &v_y.to_le_bytes()[..8];
            vm.write_memory(v_x as usize, data)
        }
        _ => InstructionResult::Panic,
    }
}

#[inline(always)]
fn get_two_immediates_params(vm: &Vm) -> (u64, u64) {
    let program = &vm.context.program;
    let bitmask = &vm.context.bitmask;
    let pc = vm.state.pc;

    let first_byte = program[pc + 1];

    let l_x = (first_byte % 8).min(4) as usize;

    let l = bitmask.skip(pc) as usize;

    let l_y = (l.saturating_sub(l_x).saturating_sub(1)).min(4);

    let v_x = decode_and_extend(program, pc + 2, l_x);

    let v_y = decode_and_extend(program, pc + 2 + l_x, l_y);

    (v_x, v_y)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_two_immediates(&mut self, opcode: u8) -> InstructionResult {
        dispatch_two_immediates(opcode, self)
    }
}
