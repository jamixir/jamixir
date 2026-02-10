use crate::context::{generate_context_token, get_context, remove_context, store_context};
use crate::memory::{get_owned, put_owned, MemoryError, MemoryRef, MemoryResource};
use crate::{
    atoms,
    nif_types::{ExecuteResult, HostOutput, VmState},
};
use pvm_core::vm::tracer::Tracer;
use pvm_core::{deblob, ExecutionResult, Vm, VmContext, VmState as CoreVmState};
use rustler::{Binary, Decoder, Encoder, Env, LocalPid, NifResult, Term};
use std::sync::Arc;

fn execute<'a>(env: Env<'a>, mut vm: Vm, context_token: u64) -> NifResult<ExecuteResult<'a>> {
    let result = vm.execute();
    let used_gas = vm.get_state().spent_gas;

    let output_bytes = match result {
        ExecutionResult::Halt => {
            let state = vm.get_state();
            let start = state.registers.data[7] as usize;
            let len = state.registers.data[8] as usize;

            if let Some(memory) = vm.get_memory() {
                memory.read(start, len).ok().map(|slice| slice.to_vec())
            } else {
                None
            }
        }
        _ => None,
    };

    match result {
        ExecutionResult::HostCall { call_id } => {
            handle_host_call(env, vm, call_id, context_token)?;
        }
        _ => {
            remove_context(context_token);
        }
    }

    Ok(ExecuteResult::from_core_result(
        env,
        result,
        used_gas,
        context_token,
        output_bytes,
    ))
}

fn handle_host_call<'a>(
    env: Env<'a>,
    mut vm: Vm,
    call_id: u64,
    context_token: u64,
) -> NifResult<()> {
    if let Some(memory) = vm.take_memory() {
        let memory_ref = MemoryResource::new_ref();
        let _ = put_owned(&memory_ref, memory);

        // Send message to Elixir with memory reference - SYNCHRONOUSLY - no OS thread
        // to avoid conflicts with QUIC and other async operations
        let pid: LocalPid = env.pid();
        let state = vm.get_state().clone();

        let message = (
            atoms::ecall(),
            call_id,
            VmState::from(state),
            memory_ref,
            context_token,
        );

        if let Err(e) = env.send(&pid, message) {
            println!("ERROR: Failed to send ecall message: {:?}", e);
        }
    }
    Ok(())
}

pub fn execute_program<'a>(
    env: Env<'a>,
    program_term: Term<'a>,
    pc_term: Term<'a>,
    gas_term: Term<'a>,
    args_term: Term<'a>,
) -> NifResult<ExecuteResult<'a>> {
    let linked_program: Binary<'a> = Binary::decode(program_term)?;
    let pc: usize = usize::decode(pc_term)?;
    let gas: u64 = u64::decode(gas_term)?;
    let args: Binary<'a> = Binary::decode(args_term)?;

    let (context, registers, memory) = match initialize_vm_context(&linked_program, &args) {
        Some(init_data) => init_data,
        None => {
            return Ok(ExecuteResult {
                used_gas: 0,
                output: HostOutput::Atom(atoms::panic()),
                context_token: 0,
            });
        }
    };

    let token = generate_context_token();
    store_context(token, context.clone());

    let state = CoreVmState::new(registers, pc, gas);
    let vm = Vm::new(context.clone(), state, Some(memory));

    execute(env, vm, token)
}

pub fn resume_execution<'a>(
    env: Env<'a>,
    new_state_term: Term<'a>,
    memory_ref_term: Term<'a>,
    context_token_term: Term<'a>,
) -> NifResult<ExecuteResult<'a>> {
    let new_state: VmState = VmState::decode(new_state_term)?;
    let memory_ref: MemoryRef = MemoryRef::decode(memory_ref_term)?;
    let context_token: u64 = u64::decode(context_token_term)?;

    let context = get_context(context_token)
        .ok_or_else(|| rustler::Error::Term(Box::new(atoms::no_vm_context())))?;

    // Convert NIF state to core state
    let core_state = CoreVmState::from(new_state);

    // Extract memory from ResourceArc
    let memory = get_owned(&memory_ref).map_err(|err| match err {
        MemoryError::MutexPoisoned => rustler::Error::Term(Box::new(atoms::mutex_poisoned())),
        MemoryError::MemoryAlreadyPresent => rustler::Error::Term(Box::new(atoms::panic())),
        MemoryError::MemoryNotPresent => rustler::Error::Term(Box::new(atoms::panic())),
    })?;

    let vm = Vm::new(context.clone(), core_state, memory);

    execute(env, vm, context_token)
}

fn initialize_vm_context(
    linked_program: &[u8],
    args: &[u8],
) -> Option<(Arc<VmContext>, pvm_core::Registers, pvm_core::Memory)> {
    let (code, registers, memory) = pvm_core::initialize_program(linked_program, args)?;

    let deblob_result = deblob(&code).ok()?;

    let start_set = pvm_core::StartSet::build(&deblob_result.program, &deblob_result.bitmask);

    let tracer = if std::env::var("PVM_TRACE").map(|v| v == "true").unwrap_or(false) {
        Some(Tracer::new())
    } else {
        None
    };

    let context = Arc::new(VmContext {
        program: deblob_result.program,
        bitmask: deblob_result.bitmask,
        jump_table: deblob_result.jump_table,
        tracer: tracer,
        start_set,
    });

    Some((context, registers, memory))
}

/// Validate a program blob by attempting to deblob it.
pub fn validate_program_blob<'a>(env: Env<'a>, program_blob: Binary<'a>) -> NifResult<Term<'a>> {
    match deblob(program_blob.as_slice()) {
        Ok(_) => Ok(atoms::ok().encode(env)),
        Err(_) => Ok((atoms::error(), atoms::invalid_program()).encode(env)),
    }
}
