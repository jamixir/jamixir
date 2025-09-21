pub mod atoms;
pub mod core;
pub mod encoding;
pub mod init_program;
pub mod types;
pub mod vm;

use rustler::{Binary, Decoder, Env, NifResult, Term};
use std::sync::{Arc, Mutex};
use std::collections::HashMap;

use crate::{
    core::errors::{to_rustler_error},
    core::StartSet,
    core::{get_owned, MemoryRef, MemoryResource},
    encoding::{deblob, Deblob},
    init_program::initialize_program,
    types::host_result::{ExecuteResult, HostOutput},
    vm::{Vm, VmContext, VmState},
};

static VM_CONTEXTS: std::sync::LazyLock<Mutex<HashMap<u64, Arc<VmContext>>>> = 
    std::sync::LazyLock::new(|| Mutex::new(HashMap::new()));

fn generate_context_token() -> u64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::{SystemTime, UNIX_EPOCH};
    use std::thread;
    
    let mut hasher = DefaultHasher::new();
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos().hash(&mut hasher);
    thread::current().id().hash(&mut hasher);
    hasher.finish()
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

    let mut vm = Vm::new(context, state, memory_ref.clone(), Some(memory), token);
    vm.arg_invoke(env)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn resume<'a>(
    env: Env<'a>,
    new_state_term: Term<'a>,
    memory_ref_term: Term<'a>,
    context_token_term: Term<'a>,
) -> NifResult<ExecuteResult> {
    let new_state: VmState = VmState::decode(new_state_term)?;
    let memory_ref: MemoryRef = MemoryRef::decode(memory_ref_term)?;
    let context_token: u64 = u64::decode(context_token_term)?;

    let context = {
        let contexts = VM_CONTEXTS.lock().unwrap();
        contexts.get(&context_token)
            .ok_or(to_rustler_error!(atoms::no_vm_context()))?
            .clone()
    };

    let memory = get_owned(&memory_ref).map_err(|_| to_rustler_error!(atoms::mutex_poisoned()))?;

    let mut vm = Vm::new(context, new_state, memory_ref, memory, context_token);
    vm.arg_invoke(env)
}
