use crate::core::{BitMask, Memory, Program, Registers, StartSet};
use crate::vm::{Vm, VmContext, VmState};
use std::sync::Arc;

pub struct VmTestBuilder {
    program: Program,
    bitmask: BitMask,
    registers: Registers,
    pc: usize,
    gas: u64,
    jump_table: Vec<usize>,
    memory: Option<Memory>,
}

impl VmTestBuilder {
    pub fn new(program_vec: Vec<u8>, bitmask_bytes: &[u8]) -> Self {
        let program = Program::from_vec(program_vec);
        let program_len = program.len();
        let bitmask = BitMask::from_bytes(bitmask_bytes, program_len);

        Self {
            program,
            bitmask,
            registers: Registers::new(),
            pc: 0,
            gas: 1000,
            jump_table: Vec::new(),
            memory: Some(Memory::test_memory(33)),
        }
    }

    pub fn with_registers(mut self, registers: Registers) -> Self {
        self.registers = registers;
        self
    }

    pub fn with_jump_table(mut self, jump_table: Vec<usize>) -> Self {
        self.jump_table = jump_table;
        self
    }

    pub fn with_memory(mut self, memory: Memory) -> Self {
        self.memory = Some(memory);
        self
    }

    pub fn build(self) -> Vm {
        let start_set = StartSet::build(&self.program, &self.bitmask);

        let context = Arc::new(VmContext {
            program: self.program,
            bitmask: self.bitmask,
            jump_table: self.jump_table,
            start_set,
        });

        let state = VmState::new(self.registers, self.pc, self.gas);

        Vm::test_instance(context, state, self.memory)
    }
}

pub const TEST_ADDR: u32 = 0x10E00;
