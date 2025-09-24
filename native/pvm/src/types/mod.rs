use crate::vm::VmState;
use rustler::NifTuple;

pub mod host_result;

#[derive(NifTuple)]
pub struct FaultResult {
    pub fault: rustler::Atom,
    pub page: usize,
    pub final_state: VmState,
}

pub enum VmExecutionOutcome {
    Halt,
    Panic,
    OutOfGas,
    Fault { page: usize },
    Waiting { call_id: u64 },
}

pub struct VmExecutionResult {
    pub outcome: VmExecutionOutcome,
    pub final_state: crate::vm::VmState,
}
