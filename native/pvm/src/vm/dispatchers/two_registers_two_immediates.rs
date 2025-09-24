use crate::vm::instructions::opcodes::*;
use crate::vm::utils::decode_and_extend;
use crate::vm::{masks, InstructionResult, Vm};

#[inline(always)]
pub fn dispatch_two_registers_two_immediates(opcode: u8, vm: &mut Vm) -> InstructionResult {
    let (r_a, r_b, v_x, v_y) = get_two_registers_two_immediates_params(vm);

    match opcode {
        LOAD_IMM_JUMP_IND => {
            let w_b = vm.state.registers.get(r_b);
            let jump_addr = (w_b.wrapping_add(v_y)) & masks::U32;

            vm.state.registers.set(r_a, v_x);

            vm.context.djump(jump_addr as usize)
        }
        _ => InstructionResult::Panic,
    }
}

#[inline(always)]
fn get_two_registers_two_immediates_params(vm: &Vm) -> (usize, usize, u64, u64) {
    let program = &vm.context.program;
    let bitmask = &vm.context.bitmask;
    let pc = vm.state.pc;

    let byte1 = program[pc + 1];
    let r_a = (byte1 & 15).min(12) as usize;
    let r_b = (byte1 >> 4).min(12) as usize;

    let byte2 = program[pc + 2];
    let l_x = (byte2 & 7).min(4) as usize;

    let l = bitmask.skip(pc);
    let l_y = (l.saturating_sub(l_x).saturating_sub(2)).min(4);

    let v_x = decode_and_extend(program, pc + 3, l_x);
    let v_y = decode_and_extend(program, pc + 3 + l_x, l_y);

    (r_a, r_b, v_x, v_y)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_two_registers_two_immediates(&mut self, opcode: u8) -> InstructionResult {
        dispatch_two_registers_two_immediates(opcode, self)
    }
}
