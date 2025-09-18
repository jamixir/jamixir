pub mod atoms;
pub mod core;
pub mod encoding;
pub mod init_program;
pub mod types;
pub mod vm;

use rustler::{Binary, Decoder, Env, NifResult, Term};
use std::sync::{Arc, OnceLock};

use crate::{
    core::errors::{to_rustler_error, ToNifResult},
    core::StartSet,
    core::{get_owned, MemoryRef, MemoryResource},
    encoding::{deblob, Deblob},
    init_program::initialize_program,
    types::host_result::{ExecuteResult, HostOutput},
    vm::{Vm, VmContext, VmState},
};

static VM_CONTEXT: OnceLock<Arc<VmContext>> = OnceLock::new();

rustler::init!("Elixir.Pvm.Native", load = load);
fn load(env: Env, _info: Term) -> bool {
    env.register::<MemoryResource>().is_ok()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn execute<'a>(
    env: Env<'a>,
    program_term: Term<'a>,
    pc_term: Term<'a>,
    gas_term: Term<'a>,
    args_term: Term<'a>,
    memory_ref_term: Term<'a>,
) -> NifResult<ExecuteResult> {
    let linked_program: Binary<'a> = Binary::decode(program_term)?;
    let pc: usize = usize::decode(pc_term)?;
    let gas: u64 = u64::decode(gas_term)?;
    let args: Binary<'a> = Binary::decode(args_term)?;
    let memory_ref: MemoryRef = MemoryRef::decode(memory_ref_term)?;

    let (code, registers, memory) = match initialize_program(&linked_program, &args) {
        None => {
            return Ok(ExecuteResult {
                used_gas: 0,
                output: HostOutput::Atom(atoms::panic()),
            });
        }
        Some(v) => v,
    };

    let Deblob {
        program,
        bitmask,
        jump_table,
    } = deblob(code);
    let start_set = StartSet::build(&program, &bitmask);

    let context = Arc::new(VmContext {
        program,
        bitmask,
        jump_table,
        start_set,
    });
    // Store context globally for resume NIF to access
    let _ = VM_CONTEXT.set(context.clone());

    let state = VmState::new(registers, pc, gas);

    Vm::new(context, state, memory_ref.clone(), Some(memory)).arg_invoke(env)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn resume<'a>(
    env: Env<'a>,
    new_state_term: Term<'a>,
    memory_ref_term: Term<'a>,
) -> NifResult<ExecuteResult> {
    let new_state: VmState = VmState::decode(new_state_term)?;
    let memory_ref: MemoryRef = MemoryRef::decode(memory_ref_term)?;

    // Get stored context from global storage
    let context = VM_CONTEXT
        .get()
        .ok_or(to_rustler_error!(atoms::no_vm_context()))?
        .clone();

    let memory = get_owned(&memory_ref).to_nif()?;

    Vm::new(context, new_state, memory_ref, memory).arg_invoke(env)
}
