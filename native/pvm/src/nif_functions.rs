use crate::child_vm;
use crate::execution::{execute_program, resume_execution};
use crate::memory::{put_owned, MemoryRef, MemoryResource};
use crate::{atoms, nif_types::ExecuteResult};
use pvm_core::Memory as CoreMemory;
use rustler::{nif, Atom, Binary, Encoder, Env, Error, NifResult, OwnedBinary, Term};

#[nif(schedule = "DirtyCpu")]
pub fn execute<'a>(
    env: Env<'a>,
    program_term: Term<'a>,
    pc_term: Term<'a>,
    gas_term: Term<'a>,
    args_term: Term<'a>,
) -> NifResult<ExecuteResult<'a>> {
    execute_program(env, program_term, pc_term, gas_term, args_term)
}

#[nif(schedule = "DirtyCpu")]
pub fn resume<'a>(
    env: Env<'a>,
    new_state_term: Term<'a>,
    memory_ref_term: Term<'a>,
    context_token_term: Term<'a>,
) -> NifResult<ExecuteResult<'a>> {
    resume_execution(env, new_state_term, memory_ref_term, context_token_term)
}

#[nif(schedule = "DirtyCpu")]
pub fn build_memory() -> MemoryRef {
    let memory_ref = MemoryResource::new_ref();
    let memory = CoreMemory::builder().build();
    let _ = put_owned(&memory_ref, memory);
    memory_ref
}

#[nif]
pub fn memory_read<'a>(
    env: Env<'a>,
    mem_ref: MemoryRef,
    addr: usize,
    len: usize,
) -> NifResult<(Atom, Term<'a>)> {
    let memory_guard = mem_ref
        .memory
        .lock()
        .map_err(|_| Error::Term(Box::new(atoms::mutex_poisoned())))?;

    match memory_guard.as_ref() {
        Some(memory) => match memory.read(addr, len) {
            Ok(slice) => {
                let mut owned_binary = OwnedBinary::new(slice.len()).unwrap();
                owned_binary.as_mut_slice().copy_from_slice(slice);
                Ok((
                    atoms::ok(),
                    Binary::from_owned(owned_binary, env).encode(env),
                ))
            }
            Err(_) => Ok((atoms::error(), atoms::panic().encode(env))),
        },
        None => Err(Error::Term(Box::new(atoms::memory_not_available()))),
    }
}

#[nif]
pub fn memory_write<'a>(
    env: Env<'a>,
    mem_ref: MemoryRef,
    addr: usize,
    data: Binary,
) -> NifResult<(Atom, Term<'a>)> {
    let mut memory_guard = mem_ref
        .memory
        .lock()
        .map_err(|_| Error::Term(Box::new(atoms::mutex_poisoned())))?;

    match memory_guard.as_mut() {
        Some(memory) => match memory.write(addr, &data) {
            Ok(_) => Ok((atoms::ok(), atoms::ok().encode(env))),
            Err(_) => Ok((atoms::error(), atoms::panic().encode(env))),
        },
        None => Err(Error::Term(Box::new(atoms::memory_not_available()))),
    }
}
#[nif]
pub fn check_memory_access(
    mem_ref: MemoryRef,
    addr: usize,
    len: usize,
    permission: u8,
) -> NifResult<bool> {
    let memory_guard = mem_ref
        .memory
        .lock()
        .map_err(|_| Error::Term(Box::new(atoms::mutex_poisoned())))?;

    match memory_guard.as_ref() {
        Some(memory) => Ok(memory.check_access(addr, len, permission.into())),
        None => Err(Error::Term(Box::new(atoms::memory_not_available()))),
    }
}
#[nif]
pub fn set_memory_access<'a>(
    mem_ref: MemoryRef,
    addr: usize,
    len: usize,
    permission: u8,
) -> NifResult<MemoryRef> {
    let mut memory_guard = mem_ref
        .memory
        .lock()
        .map_err(|_| Error::Term(Box::new(atoms::mutex_poisoned())))?;

    match memory_guard.as_mut() {
        Some(memory) => {
            memory.set_access(addr, len, permission.into());
            Ok(mem_ref.clone())
        }
        None => Err(Error::Term(Box::new(atoms::memory_not_available()))),
    }
}

#[nif(schedule = "DirtyCpu")]
pub fn validate_program_blob<'a>(env: Env<'a>, program_blob: Binary<'a>) -> NifResult<Term<'a>> {
    crate::execution::validate_program_blob(env, program_blob)
}

// ===== child VM Instance NIFs =====

#[nif(schedule = "DirtyCpu")]
pub fn create_child_vm<'a>(
    env: Env<'a>,
    program_blob: Binary<'a>,
    initial_pc: Term<'a>,
    initial_gas: Term<'a>,
    initial_registers: Term<'a>,
) -> NifResult<Term<'a>> {
    child_vm::create_instance(
        env,
        program_blob,
        initial_pc,
        initial_gas,
        initial_registers,
    )
}

#[nif(schedule = "DirtyCpu")]
pub fn execute_child_vm<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    gas: Term<'a>,
    registers: Term<'a>,
) -> NifResult<Term<'a>> {
    child_vm::execute(env, instance_ref, gas, registers)
}
#[nif]
pub fn child_vm_read_memory<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    addr: Term<'a>,
    len: Term<'a>,
) -> NifResult<Term<'a>> {
    child_vm::read_memory(env, instance_ref, addr, len)
}
#[nif]
pub fn child_vm_write_memory<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    addr: Term<'a>,
    data: Binary<'a>,
) -> NifResult<Term<'a>> {
    child_vm::write_memory(env, instance_ref, addr, data)
}
#[nif]
pub fn get_child_vm_state<'a>(env: Env<'a>, instance_ref: Term<'a>) -> NifResult<Term<'a>> {
    child_vm::get_state(env, instance_ref)
}
#[nif]
pub fn destroy_child_vm<'a>(env: Env<'a>, instance_ref: Term<'a>) -> NifResult<Term<'a>> {
    child_vm::destroy(env, instance_ref)
}

#[nif]
pub fn set_child_vm_memory_access<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    page_index: Term<'a>,
    page_count: Term<'a>,
    permission: Term<'a>,
) -> NifResult<Term<'a>> {
    child_vm::set_memory_access(env, instance_ref, page_index, page_count, permission)
}
#[nif]
pub fn check_child_vm_memory_access<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    page_index: Term<'a>,
    page_count: Term<'a>,
    required_permission: Term<'a>,
) -> NifResult<Term<'a>> {
    child_vm::check_memory_access(
        env,
        instance_ref,
        page_index,
        page_count,
        required_permission,
    )
}
#[nif]
pub fn child_vm_zero_memory<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    addr: Term<'a>,
    len: Term<'a>,
) -> NifResult<Term<'a>> {
    child_vm::zero_memory(env, instance_ref, addr, len)
}
