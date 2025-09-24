use crate::vm::instructions::opcodes::*;
use crate::vm::{InstructionResult, Vm};

#[inline(always)]
pub fn dispatch_no_args(opcode: u8) -> InstructionResult {
    match opcode {
        TRAP => InstructionResult::Panic,
        FALLTHROUGH => InstructionResult::Continue,
        _ => InstructionResult::Panic,
    }
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_no_args(&self, opcode: u8) -> InstructionResult {
        dispatch_no_args(opcode)
    }
}
