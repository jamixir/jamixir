use crate::core::{BitMask, Program, Registers, StartSet};
use rustler::NifStruct;
#[derive(Debug, Clone, PartialEq)]

pub enum InstructionResult {
    Continue,
    Jump(usize),
    Halt,
    Panic,
    Fault { page: usize },
    Ecall { call_id: u64 },
}
pub enum StepResult {
    Continue,
    Halt,
    Panic,
    Fault { page: usize },
    Ecall { call_id: u64 },
}

impl From<InstructionResult> for StepResult {
    fn from(instruction_result: InstructionResult) -> Self {
        match instruction_result {
            InstructionResult::Continue => StepResult::Continue,
            InstructionResult::Jump(..) => StepResult::Continue,
            InstructionResult::Halt => StepResult::Halt,
            InstructionResult::Panic => StepResult::Panic,
            InstructionResult::Fault { page } => StepResult::Fault { page },
            InstructionResult::Ecall { call_id } => StepResult::Ecall { call_id },
        }
    }
}

#[derive(Debug, Clone, NifStruct, Copy)]
#[module = "Pvm.Native.VmState"]
pub struct VmState {
    pub registers: Registers,
    pub pc: usize,
    pub initial_gas: u64,
    pub spent_gas: u64,
}

impl VmState {
    pub fn new(registers: Registers, pc: usize, gas: u64) -> Self {
        Self {
            registers,
            pc,
            initial_gas: gas,
            spent_gas: 0,
        }
    }

    pub fn consume_gas(&mut self, amount: u64) {
        self.spent_gas += amount;
    }

    pub fn has_gas(&self) -> bool {
        self.initial_gas >= self.spent_gas
    }
}

#[derive(Debug)]
pub struct VmContext {
    pub program: Program,
    pub bitmask: BitMask,
    pub jump_table: Vec<usize>,
    pub start_set: StartSet,
}

impl VmContext {
    #[inline(always)]
    pub fn branch(&self, destination: usize, should_branch: bool) -> InstructionResult {
        match (should_branch, self.start_set.includes(destination)) {
            (true, true) => InstructionResult::Jump(destination),
            (true, false) => InstructionResult::Panic,
            (false, _) => InstructionResult::Continue,
        }
    }

    pub fn djump(&self, destination: usize) -> InstructionResult {
        match destination {
            0xFFFF0000 => InstructionResult::Halt,
            0 => InstructionResult::Panic,
            destination if destination > (self.jump_table.len() << 2) => InstructionResult::Panic,
            _ if destination & 0b1 != 0 => InstructionResult::Panic,
            _ => {
                let jump_to = self.jump_table[(destination >> 1) - 1];
                if self.start_set.includes(jump_to) {
                    InstructionResult::Jump(jump_to)
                } else {
                    InstructionResult::Panic
                }
            }
        }
    }
}

#[derive(Debug)]
pub enum ExecutionResult {
    Halt,
    Panic,
    OutOfGas,
    Fault { page: usize },
    HostCall { call_id: u64 },
}

impl From<StepResult> for ExecutionResult {
    fn from(exit_reason: StepResult) -> Self {
        match exit_reason {
            StepResult::Continue => ExecutionResult::OutOfGas,
            StepResult::Halt => ExecutionResult::Halt,
            StepResult::Panic => ExecutionResult::Panic,
            StepResult::Fault { page } => ExecutionResult::Fault { page },
            StepResult::Ecall { call_id } => ExecutionResult::HostCall { call_id },
        }
    }
}
