use crate::vm::instructions::opcodes::*;
use crate::vm::utils::{sign_extend, unsigned_to_signed};
use crate::vm::{masks, InstructionResult, Vm};
use std::cmp::{max, min};

#[inline(always)]
pub fn dispatch_three_registers(opcode: u8, vm: &mut Vm) -> InstructionResult {
    let (w_a, w_b, r_d) = get_three_registers_params(vm);

    match opcode {
        ADD_32 => {
            let result = (w_a.wrapping_add(w_b)) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SUB_32 => {
            let result = (w_a & masks::U32).wrapping_sub(w_b & masks::U32) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MUL_32 => {
            let result = (w_a.wrapping_mul(w_b)) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        DIV_U_32 => {
            let a = w_a & masks::U32;
            let b = w_b & masks::U32;
            let result = if b == 0 {
                u64::MAX
            } else {
                let div_result = a / b;
                sign_extend(div_result, 4)
            };
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        DIV_S_32 => {
            let a = unsigned_to_signed(w_a & masks::U32, 4);
            let b = unsigned_to_signed(w_b & masks::U32, 4);

            let result = if b == 0 {
                u64::MAX
            } else if b == -1 && a == -(1i64 << 31) {
                sign_extend(a as u64, 8)
            } else {
                let div_result = (a / b) as u64;
                sign_extend(div_result, 8)
            };

            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        REM_U_32 => {
            let a = w_a & masks::U32;
            let b = w_b & masks::U32;
            let remainder = if b == 0 { a } else { a % b };
            let result = sign_extend(remainder, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        REM_S_32 => {
            let a = unsigned_to_signed(w_a & masks::U32, 4);
            let b = unsigned_to_signed(w_b & masks::U32, 4);
            let result = if b == -1 && a == -(1i64 << 31) {
                0
            } else {
                let remainder = signed_rem(a, b);
                sign_extend(remainder as u64, 8)
            };
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SHLO_L_32 => {
            let shift = w_b & 31;
            let result = ((w_a & masks::U32) << shift) & masks::U32;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SHLO_R_32 => {
            let shift = w_b & 31;
            let result = (w_a & masks::U32) >> shift;
            let result = sign_extend(result, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SHAR_R_32 => {
            let shift = w_b & 31;
            let signed_a = unsigned_to_signed(w_a & masks::U32, 4);
            let result = sign_extend((signed_a >> shift) as u64, 8);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        ADD_64 => {
            let result = w_a.wrapping_add(w_b);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SUB_64 => {
            let result = w_a.wrapping_sub(w_b);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MUL_64 => {
            let result = w_a.wrapping_mul(w_b);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        DIV_U_64 => {
            let result = if w_b == 0 { u64::MAX } else { w_a / w_b };
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        DIV_S_64 => {
            let a = unsigned_to_signed(w_a, 8);
            let b = unsigned_to_signed(w_b, 8);

            let result = if b == 0 {
                u64::MAX
            } else {
                let signed_result = a.wrapping_div(b);
                sign_extend(signed_result as u64, 8)
            };
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        REM_U_64 => {
            let result = if w_b == 0 { w_a } else { w_a % w_b };
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        REM_S_64 => {
            let a = unsigned_to_signed(w_a, 8);
            let b = unsigned_to_signed(w_b, 8);
            let result = if b == -1 && a == i64::MIN {
                0
            } else {
                let remainder = signed_rem(a, b);
                sign_extend(remainder as u64, 8)
            };
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SHLO_L_64 => {
            let shift = w_b & 63;
            let result = w_a << shift;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SHLO_R_64 => {
            let shift = w_b & 63;
            let result = w_a >> shift;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SHAR_R_64 => {
            let shift = w_b & 63;
            let signed_a = w_a as i64;
            let result = (signed_a >> shift) as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        AND => {
            let result = w_a & w_b;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        XOR => {
            let result = w_a ^ w_b;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        OR => {
            let result = w_a | w_b;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        AND_INV => {
            let result = w_a & !w_b;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        OR_INV => {
            let result = w_a | !w_b;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        XNOR => {
            let result = !(w_a ^ w_b);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MUL_UPPER_S_S => {
            let a = unsigned_to_signed(w_a, 8);
            let b = unsigned_to_signed(w_b, 8);
            let product = (a as i128 * b as i128) >> 64;
            let result = product as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MUL_UPPER_U_U => {
            let result = ((w_a as u128 * w_b as u128) >> 64) as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MUL_UPPER_S_U => {
            let a = unsigned_to_signed(w_a, 8);
            let product = (a as i128 * w_b as i128) >> 64;
            let result = product as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SET_LT_U => {
            let result = (w_a < w_b) as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SET_LT_S => {
            let result = (unsigned_to_signed(w_a, 8) < unsigned_to_signed(w_b, 8)) as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        CMOV_IZ => {
            let w_d = vm.state.registers.get(r_d);
            let result = w_d.wrapping_add((w_a.wrapping_sub(w_d)).wrapping_mul((w_b == 0) as u64));
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        CMOV_NZ => {
            let w_d = vm.state.registers.get(r_d);
            let result = w_d.wrapping_add((w_a.wrapping_sub(w_d)).wrapping_mul((w_b != 0) as u64));
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        ROT_L_64 => {
            let result = w_a.rotate_left(w_b as u32);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        ROT_L_32 => {
            let val32 = (w_a & masks::U32) as u32;
            let shift = (w_b & 31) as u32;
            let result = sign_extend(val32.rotate_left(shift) as u64, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        ROT_R_64 => {
            let result = w_a.rotate_right(w_b as u32);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        ROT_R_32 => {
            let val32 = (w_a & masks::U32) as u32;
            let shift = (w_b & 31) as u32;
            let result = sign_extend(val32.rotate_right(shift) as u64, 4);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MAX => {
            let result = max(unsigned_to_signed(w_a, 8), unsigned_to_signed(w_b, 8)) as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MAX_U => {
            vm.state.registers.set(r_d, max(w_a, w_b));
            InstructionResult::Continue
        }
        MIN => {
            let result = min(unsigned_to_signed(w_a, 8), unsigned_to_signed(w_b, 8)) as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        MIN_U => {
            vm.state.registers.set(r_d, min(w_a, w_b));
            InstructionResult::Continue
        }
        _ => InstructionResult::Panic,
    }
}

#[inline(always)]
fn get_three_registers_params(vm: &Vm) -> (u64, u64, usize) {
    let program = &vm.context.program;
    let pc = vm.state.pc;

    let byte1 = program[pc + 1];
    let byte2 = program[pc + 2];

    let r_a = (byte1 & 15).min(12) as usize;
    let r_b = (byte1 >> 4).min(12) as usize;
    let r_d = byte2.min(12) as usize;

    let w_a = vm.state.registers.get(r_a);
    let w_b = vm.state.registers.get(r_b);

    (w_a, w_b, r_d)
}

#[inline(always)]
fn signed_rem(a: i64, b: i64) -> i64 {
    match b {
        0 => a,
        _ => a % b,
    }
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_three_registers(&mut self, opcode: u8) -> InstructionResult {
        dispatch_three_registers(opcode, self)
    }
}
