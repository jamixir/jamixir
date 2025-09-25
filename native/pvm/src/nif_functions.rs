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

#[nif]
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
