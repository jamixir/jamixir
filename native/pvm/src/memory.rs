use pvm_core::Memory;
use rustler::{Resource, ResourceArc};
use std::sync::Mutex;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MemoryError {
    MutexPoisoned,
    MemoryAlreadyPresent,
    MemoryNotPresent,
}

#[derive(Debug)]
pub struct MemoryResource {
    pub memory: Mutex<Option<Memory>>,
}

impl Resource for MemoryResource {}

impl MemoryResource {
    pub fn new() -> Self {
        Self {
            memory: Mutex::new(None),
        }
    }

    pub fn new_ref() -> ResourceArc<Self> {
        ResourceArc::new(Self::new())
    }
}

pub type MemoryRef = ResourceArc<MemoryResource>;

pub fn get_owned(mem_ref: &MemoryRef) -> Result<Option<Memory>, MemoryError> {
    let mut guard = mem_ref
        .memory
        .lock()
        .map_err(|_| MemoryError::MutexPoisoned)?;
    Ok(guard.take())
}

pub fn put_owned(mem_ref: &MemoryRef, memory: Memory) -> Result<(), MemoryError> {
    let mut guard = mem_ref
        .memory
        .lock()
        .map_err(|_| MemoryError::MutexPoisoned)?;
    if guard.is_none() {
        *guard = Some(memory);
        Ok(())
    } else {
        Err(MemoryError::MemoryAlreadyPresent)
    }
}
