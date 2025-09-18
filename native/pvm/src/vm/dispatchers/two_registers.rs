use crate::core::Permission;
use crate::vm::instructions::opcodes::*;
use crate::vm::utils::sign_extend;
use crate::vm::{masks, InstructionResult, Vm};

#[inline(always)]
pub fn dispatch_two_registers(opcode: u8, vm: &mut Vm) -> InstructionResult {
    let (w_a, r_d) = get_two_registers_params(vm);

    match opcode {
        MOVE_REG => {
            vm.state.registers.set(r_d, w_a);
            InstructionResult::Continue
        }
        SBRK => handle_sbrk(w_a, r_d, vm),
        COUNT_SET_BITS_64 => {
            let result = w_a.count_ones() as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        COUNT_SET_BITS_32 => {
            let result = (w_a & masks::U32).count_ones() as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        LEADING_ZERO_BITS_64 => {
            let result = w_a.leading_zeros() as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        LEADING_ZERO_BITS_32 => {
            let result = if w_a & masks::U32 == 0 {
                32
            } else {
                (w_a & masks::U32).leading_zeros().saturating_sub(32)
            } as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        TRAILING_ZERO_BITS_64 => {
            let result = if w_a == 0 { 64 } else { w_a.trailing_zeros() } as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        TRAILING_ZERO_BITS_32 => {
            let val32 = w_a & masks::U32;
            let result = if val32 == 0 {
                32
            } else {
                val32.trailing_zeros()
            } as u64;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SIGN_EXTEND_8 => {
            let val8 = w_a & masks::U8;
            let result = sign_extend(val8, 1);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        SIGN_EXTEND_16 => {
            let val16 = w_a & masks::U16;
            let result = sign_extend(val16, 2);
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        ZERO_EXTEND_16 => {
            let result = w_a & masks::U16;
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        REVERSE_BYTES => {
            let result = w_a.swap_bytes();
            vm.state.registers.set(r_d, result);
            InstructionResult::Continue
        }
        _ => InstructionResult::Panic,
    }
}

#[inline(always)]
fn handle_sbrk(size: u64, r_d: usize, vm: &mut Vm) -> InstructionResult {
    let memory = vm.memory.as_mut().expect("Memory not available");

    if size == 0 {
        // Query current heap pointer
        vm.state
            .registers
            .set(r_d, memory.current_heap_pointer as u64);
        return InstructionResult::Continue;
    }

    let new_heap_pointer = memory.current_heap_pointer.wrapping_add(size as usize);

    // Check if allocation would exceed heap bounds
    if new_heap_pointer > memory.max_heap_pointer {
        // Allocation failed
        vm.state.registers.set(r_d, 0);
        return InstructionResult::Continue;
    }

    let old_heap_pointer = memory.current_heap_pointer;

    // Check if the memory range is writable
    if !memory.check_access(old_heap_pointer, size as usize, Permission::ReadWrite) {
        // Set write permissions for the allocated range
        memory.set_access(old_heap_pointer, size as usize, Permission::ReadWrite);
    }

    // Update heap pointer and return old pointer
    memory.current_heap_pointer = new_heap_pointer;
    vm.state.registers.set(r_d, old_heap_pointer as u64);
    InstructionResult::Continue
}

// Formula (A.27) v0.7.0
#[inline(always)]
fn get_two_registers_params(vm: &Vm) -> (u64, usize) {
    let program = &vm.context.program;
    let pc = vm.state.pc;

    let byte = program[pc + 1];
    let r_a = (byte >> 4).min(12) as usize;
    let r_d = (byte & 0x0F).min(12) as usize;

    let w_a = vm.state.registers.get(r_a);

    (w_a, r_d)
}

impl Vm {
    #[inline(always)]
    pub fn dispatch_two_registers(&mut self, opcode: u8) -> InstructionResult {
        dispatch_two_registers(opcode, self)
    }
}
