use crate::core::Program;
use crate::vm::{InstructionResult, Vm};

impl Vm {
    pub fn next_counter(&self, exit_reason: &InstructionResult, prev_counter: usize) -> usize {
        match exit_reason {
            InstructionResult::Continue => {
                prev_counter + 1 + self.context.bitmask.skip(prev_counter)
            }
            InstructionResult::Ecall { .. } => {
                prev_counter + 1 + self.context.bitmask.skip(prev_counter)
            }
            InstructionResult::Jump(destination) => *destination,
            InstructionResult::Halt => 0,
            InstructionResult::Panic => 0,
            InstructionResult::Fault { .. } => prev_counter,
        }
    }
}

#[inline(always)]
pub fn decode_and_extend(program: &Program, start_index: usize, count: usize) -> u64 {
    let mut x: u64 = 0;
    for i in 0..count {
        x |= (program[start_index + i] as u64) << (8 * i);
    }
    sign_extend(x, count)
}

/// Extend value to 64-bit
#[inline(always)]
pub fn sign_extend(x: u64, n: usize) -> u64 {
    let shift = (64u32.wrapping_sub((n * 8) as u32)) & 63;
    ((x << shift) as i64 >> shift) as u64
}
#[inline(always)]
pub fn decode_bytes(program: &Program, start_index: usize, count: usize) -> u64 {
    let mut buf = [0u8; 8];
    let count = count.min(8);
    buf[..count].copy_from_slice(&program[start_index..start_index + count]);
    u64::from_le_bytes(buf)
}

#[inline(always)]
pub fn unsigned_to_signed(x: u64, num_bytes: usize) -> i64 {
    sign_extend(x, num_bytes) as i64
}
