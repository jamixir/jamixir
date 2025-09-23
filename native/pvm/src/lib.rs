pub mod atoms;
pub mod core;
pub mod encoding;
pub mod init_program;
pub mod types;
pub mod vm;

use rustler::{Binary, Decoder, Env, NifResult, Term};
use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, LazyLock, Mutex,
};

use crate::{
    core::errors::to_rustler_error,
    core::StartSet,
    core::{get_owned, MemoryRef, MemoryResource},
    encoding::{deblob, Deblob},
    init_program::initialize_program,
    types::host_result::{ExecuteResult, HostOutput},
    vm::{Vm, VmContext, VmState},
};

static NEXT_CTX_ID: AtomicU64 = AtomicU64::new(1);

static VM_CONTEXTS: LazyLock<Mutex<HashMap<u64, Arc<VmContext>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn generate_context_token() -> u64 {
    NEXT_CTX_ID.fetch_add(1, Ordering::Relaxed)
}

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
) -> NifResult<ExecuteResult<'a>> {
    let linked_program: Binary<'a> = Binary::decode(program_term)?;
    let pc: usize = usize::decode(pc_term)?;
    let gas: u64 = u64::decode(gas_term)?;
    let args: Binary<'a> = Binary::decode(args_term)?;

    let (code, registers, memory) = match initialize_program(&linked_program, &args) {
        None => {
            return Ok(ExecuteResult {
                used_gas: 0,
                output: HostOutput::Atom(atoms::panic()),
                context_token: 0,
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

    let token = generate_context_token();
    {
        let mut contexts = VM_CONTEXTS.lock().unwrap();
        contexts.insert(token, context.clone());
    }

    let state = VmState::new(registers, pc, gas);
    let memory_ref = MemoryResource::new_ref();

    let mut vm = Vm::new(context.clone(), state, memory_ref, Some(memory), token);

    let result = vm.arg_invoke(env)?;

    if !result.is_waiting() {
        let mut contexts = VM_CONTEXTS.lock().unwrap();
        contexts.remove(&token);
    }

    Ok(result)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn resume<'a>(
    env: Env<'a>,
    new_state_term: Term<'a>,
    memory_ref_term: Term<'a>,
    context_token_term: Term<'a>,
) -> NifResult<ExecuteResult<'a>> {
    let new_state: VmState = VmState::decode(new_state_term)?;
    let memory_ref: MemoryRef = MemoryRef::decode(memory_ref_term)?;
    let context_token: u64 = u64::decode(context_token_term)?;

    let context = {
        let contexts = VM_CONTEXTS.lock().unwrap();
        contexts
            .get(&context_token)
            .ok_or(to_rustler_error!(atoms::no_vm_context()))?
            .clone()
    };

    let memory = get_owned(&memory_ref).map_err(|_| to_rustler_error!(atoms::mutex_poisoned()))?;

    let mut vm = Vm::new(
        context.clone(),
        new_state,
        memory_ref.clone(),
        memory,
        context_token,
    );

    let result = vm.arg_invoke(env)?;

    if !result.is_waiting() {
        let mut contexts = VM_CONTEXTS.lock().unwrap();
        contexts.remove(&context_token);
    }

    Ok(result)
}
