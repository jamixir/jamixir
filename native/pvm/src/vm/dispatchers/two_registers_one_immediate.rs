use crate::core::MemoryError;
use crate::encoding::decode_le;
use crate::vm::instructions::opcodes::*;
use crate::vm::utils::{decode_and_extend, sign_extend, unsigned_to_signed};
use crate::vm::{masks, InstructionResult, Vm};

#[inline(always)]
pub fn dispatch_two_registers_one_immediate(opcode: u8, vm: &mut Vm) -> InstructionResult {
    let (r_a, r_b, v_x) = get_two_registers_one_immediate_params(vm);

    match opcode {
        // Store instructions
        STORE_IND_U8 => {
            let w_a = vm.state.registers.get(r_a);
            let w_b = vm.state.registers.get(r_b);
            let value = (w_a & masks::U8) as u8;
            let addr = w_b.wrapping_add(v_x);
            let data = &[value];
            vm.write_memory(addr as usize, data)
        }
        STORE_IND_U16 => {
            let w_a = vm.state.registers.get(r_a);
            let w_b = vm.state.registers.get(r_b);
            let value = (w_a & masks::U16) as u16;
            let addr = w_b.wrapping_add(v_x);
            let data = &value.to_le_bytes()[..2];
            vm.write_memory(addr as usize, data)
        }
        STORE_IND_U32 => {
            let w_a = vm.state.registers.get(r_a);
            let w_b = vm.state.registers.get(r_b);
            let value = (w_a & masks::U32) as u32;
            let addr = w_b.wrapping_add(v_x);
            let data = &value.to_le_bytes()[..4];
            vm.write_memory(addr as usize, data)
        }
        STORE_IND_U64 => {
            let w_a = vm.state.registers.get(r_a);
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            let data = &w_a.to_le_bytes()[..8];
            vm.write_memory(addr as usize, data)
        }

        // Load instructions (unsigned)
        LOAD_IND_U8 => {
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            match vm.read_memory(addr as usize, 1) {
                Ok(data) => {
                    let value = data[0] as u64;
                    vm.state.registers.set(r_a, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_IND_U16 => {
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            match vm.read_memory(addr as usize, 2) {
                Ok(data) => {
                    let value = decode_le(data, 2);
                    vm.state.registers.set(r_a, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_IND_U32 => {
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            match vm.read_memory(addr as usize, 4) {
                Ok(data) => {
                    let value = decode_le(data, 4);
                    vm.state.registers.set(r_a, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_IND_U64 => {
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            match vm.read_memory(addr as usize, 8) {
                Ok(data) => {
                    let value = decode_le(data, 8);
                    vm.state.registers.set(r_a, value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }

        // Load instructions (signed)
        LOAD_IND_I8 => {
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            match vm.read_memory(addr as usize, 1) {
                Ok(data) => {
                    let value = data[0] as u64;
                    let signed_value = sign_extend(value, 1);
                    vm.state.registers.set(r_a, signed_value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_IND_I16 => {
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            match vm.read_memory(addr as usize, 2) {
                Ok(data) => {
                    let value = decode_le(data, 2);
                    let signed_value = sign_extend(value, 2);
                    vm.state.registers.set(r_a, signed_value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }
        LOAD_IND_I32 => {
            let w_b = vm.state.registers.get(r_b);
            let addr = w_b.wrapping_add(v_x);
            match vm.read_memory(addr as usize, 4) {
                Ok(data) => {
                    let value = decode_le(data, 4);
                    let signed_value = sign_extend(value, 4);
                    vm.state.registers.set(r_a, signed_value);
                    InstructionResult::Continue
                }
                Err(MemoryError::Fault { page_addr }) => {
                    InstructionResult::Fault { page: page_addr }
                }
                Err(MemoryError::Panic) => InstructionResult::Panic,
            }
        }

        // Arithmetic instructions (32-bit)
        ADD_IMM_32 => {
            let w_b = vm.state.registers.get(r_b);
            let result = (w_b.wrapping_add(v_x)) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        MUL_IMM_32 => {
            let w_b = vm.state.registers.get(r_b);
            let result = (w_b.wrapping_mul(v_x)) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        NEG_ADD_IMM_32 => {
            let w_b = vm.state.registers.get(r_b);
            let result = (v_x.wrapping_sub(w_b)) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Bitwise instructions
        AND_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let result = w_b & v_x;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        XOR_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let result = w_b ^ v_x;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        OR_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let result = w_b | v_x;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Comparison instructions
        SET_LT_U_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let result = (w_b < v_x) as u64;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SET_LT_S_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let w_b_signed = unsigned_to_signed(w_b, 8);
            let v_x_signed = unsigned_to_signed(v_x, 8);
            let result = (w_b_signed < v_x_signed) as u64;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SET_GT_U_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let result = (w_b > v_x) as u64;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SET_GT_S_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let w_b_signed = unsigned_to_signed(w_b, 8);
            let v_x_signed = unsigned_to_signed(v_x, 8);
            let result = (w_b_signed > v_x_signed) as u64;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Shift instructions (32-bit)
        SHLO_L_IMM_32 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 31) as u32;
            let result = ((w_b & masks::U32) << shift) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHLO_R_IMM_32 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 31) as u32;
            let result = (w_b & masks::U32) >> shift;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHAR_R_IMM_32 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 31) as u32;
            let signed_b = unsigned_to_signed(w_b & masks::U32, 4);
            let result = sign_extend((signed_b >> shift) as u64, 8);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Alternative shift instructions (32-bit)
        SHLO_L_IMM_ALT_32 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 31) as u32;
            let result = ((v_x & masks::U32) << shift) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHLO_R_IMM_ALT_32 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 31) as u32;
            let result = (v_x & masks::U32) >> shift;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHAR_R_IMM_ALT_32 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 31) as u32;
            let signed_x = unsigned_to_signed(v_x & masks::U32, 4);
            let result = sign_extend((signed_x >> shift) as u64, 8);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Conditional move instructions
        CMOV_IZ_IMM => {
            let w_a = vm.state.registers.get(r_a);
            let w_b = vm.state.registers.get(r_b);
            let diff = v_x.wrapping_sub(w_a);

            let result = w_a.wrapping_add(diff * (w_b == 0) as u64);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        CMOV_NZ_IMM => {
            let w_a = vm.state.registers.get(r_a);
            let w_b = vm.state.registers.get(r_b);
            let diff = v_x.wrapping_sub(w_a);
            let result = w_a.wrapping_add(diff * (w_b != 0) as u64);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Arithmetic instructions (64-bit)
        ADD_IMM_64 => {
            let w_b = vm.state.registers.get(r_b);
            let result = w_b.wrapping_add(v_x);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        MUL_IMM_64 => {
            let w_b = vm.state.registers.get(r_b);
            let result = w_b.wrapping_mul(v_x);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        NEG_ADD_IMM_64 => {
            let w_b = vm.state.registers.get(r_b);
            let result = v_x.wrapping_sub(w_b);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Shift instructions (64-bit)
        SHLO_L_IMM_64 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 63) as u32;
            let result = w_b.wrapping_shl(shift);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHLO_R_IMM_64 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 63) as u32;
            let result = w_b >> shift;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHAR_R_IMM_64 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 63) as u32;
            let signed_b = unsigned_to_signed(w_b, 8);
            let result = sign_extend((signed_b >> shift) as u64, 8);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Alternative shift instructions (64-bit)
        SHLO_L_IMM_ALT_64 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 63) as u32;
            let result = v_x.wrapping_shl(shift);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHLO_R_IMM_ALT_64 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 63) as u32;
            let result = v_x >> shift;
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        SHAR_R_IMM_ALT_64 => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 63) as u32;
            let signed_x = unsigned_to_signed(v_x, 8);
            let result = sign_extend((signed_x >> shift) as u64, 8);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        // Rotation instructions
        ROT_R_64_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 63) as u32;
            let result = w_b.rotate_right(shift);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        ROT_R_64_IMM_ALT => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 63) as u32;
            let result = v_x.rotate_right(shift);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        ROT_R_32_IMM => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (v_x & 31) as u32;
            let val32 = (w_b & masks::U32) as u32;
            let result = val32.rotate_right(shift) as u64;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }
        ROT_R_32_IMM_ALT => {
            let w_b = vm.state.registers.get(r_b);
            let shift = (w_b & 31) as u32;
            let val32 = (v_x & masks::U32) as u32;
            let result = val32.rotate_right(shift) as u64;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_a, result);
            InstructionResult::Continue
        }

        _ => InstructionResult::Panic,
    }
}

// Formula (A.28) v0.7.0
#[inline(always)]
fn get_two_registers_one_immediate_params(vm: &Vm) -> (usize, usize, u64) {
    let program = &vm.context.program;
    let bitmask = &vm.context.bitmask;
    let pc = vm.state.pc;

    let byte1 = program[pc + 1];
    let r_a = (byte1 & 0x0F).min(12) as usize;
    let r_b = (byte1 >> 4).min(12) as usize;

    let l_x = (bitmask.skip(pc).saturating_sub(1)).min(4);

    let v_x = decode_and_extend(program, pc + 2, l_x);

    (r_a, r_b, v_x)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_two_registers_one_immediate(&mut self, opcode: u8) -> InstructionResult {
        dispatch_two_registers_one_immediate(opcode, self)
    }
}
