use crate::core::MemoryError;
use crate::encoding::decode_le;
use crate::vm::instructions::opcodes::*;
use crate::vm::utils::{decode_and_extend, decode_bytes, sign_extend};
use crate::vm::{masks, InstructionResult, Vm, VmContext};

#[inline(always)]
pub fn dispatch_reg_immediate(opcode: u8, vm: &mut Vm) -> InstructionResult {
    match opcode {
        LOAD_IMM_64 => {
            let program = &vm.context.program;
            let pc = vm.state.pc;
            let register_index = (program[pc + 1] & 0x0F).min(12) as usize;
            let value = decode_bytes(program, pc + 2, 8);

            vm.state.registers.set(register_index, value);
            InstructionResult::Continue
        }
        JUMP_IND => {
            let (register_index, value) = get_reg_immediate_params(&vm.context, vm.state.pc);
            let register_value = vm.state.registers.get(register_index);
            let target = ((register_value.wrapping_add(value)) & masks::U32) as usize;
            vm.context.djump(target)
        }
        LOAD_IMM => {
            let (register_index, value) = get_reg_immediate_params(&vm.context, vm.state.pc);
            vm.state.registers.set(register_index, value);
            InstructionResult::Continue
        }
        LOAD_U8 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            match vm.read_memory(address as usize, 1) {
                Ok(data) => {
                    let value = data[0] as u64;
                    vm.state.registers.set(register_index, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_I8 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            match vm.read_memory(address as usize, 1) {
                Ok(data) => {
                    let value = data[0] as u64;
                    let signed_value = sign_extend(value, 1);
                    vm.state.registers.set(register_index, signed_value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_U16 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            match vm.read_memory(address as usize, 2) {
                Ok(data) => {
                    let value = decode_le(data, 2);
                    vm.state.registers.set(register_index, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_I16 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            match vm.read_memory(address as usize, 2) {
                Ok(data) => {
                    let value = decode_le(data, 2);
                    let signed_value = sign_extend(value, 2);
                    vm.state.registers.set(register_index, signed_value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_U32 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            match vm.read_memory(address as usize, 4) {
                Ok(data) => {
                    let value = decode_le(data, 4);
                    vm.state.registers.set(register_index, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_I32 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            match vm.read_memory(address as usize, 4) {
                Ok(data) => {
                    let value = decode_le(data, 4);
                    let signed_value = sign_extend(value, 4);
                    vm.state.registers.set(register_index, signed_value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_U64 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            match vm.read_memory(address as usize, 8) {
                Ok(data) => {
                    let value = decode_le(data, 8);
                    vm.state.registers.set(register_index, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        STORE_U8 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            let value = vm.state.registers.get(register_index);
            let stored_value = (value & masks::U8) as u8;
            let data = &[stored_value];
            vm.write_memory(address as usize, data)
        }
        STORE_U16 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            let value = vm.state.registers.get(register_index);
            let stored_value = (value & masks::U16) as u16;
            let data = &stored_value.to_le_bytes()[..2];
            vm.write_memory(address as usize, data)
        }
        STORE_U32 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            let value = vm.state.registers.get(register_index);
            let stored_value = (value & masks::U32) as u32;
            let data = &stored_value.to_le_bytes()[..4];
            vm.write_memory(address as usize, data)
        }
        STORE_U64 => {
            let (register_index, address) = get_reg_immediate_params(&vm.context, vm.state.pc);
            let value = vm.state.registers.get(register_index);
            let data = &value.to_le_bytes()[..8];
            vm.write_memory(address as usize, data)
        }
        _ => InstructionResult::Panic,
    }
}

#[inline(always)]
fn get_reg_immediate_params(context: &VmContext, pc: usize) -> (usize, u64) {
    let program = &context.program;
    let bitmask = &context.bitmask;

    let register_index = (program[pc + 1] & 0x0F).min(12) as usize;
    let l_x = (bitmask.skip(pc).saturating_sub(1)).min(4) as usize;
    let value = decode_and_extend(program, pc + 2, l_x);

    (register_index, value)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_reg_immediate(&mut self, opcode: u8) -> InstructionResult {
        dispatch_reg_immediate(opcode, self)
    }
}
