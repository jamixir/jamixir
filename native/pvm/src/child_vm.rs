use crate::atoms;
use crate::nif_types::{Registers, VmState};
use pvm_core::{ChildVmInstance, ExecutionResult, Registers as CoreRegisters};
use rustler::{Binary, Decoder, Encoder, Env, NifResult, ResourceArc, Term};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

pub struct ChildVmResource {
    pub instance: Mutex<ChildVmInstance>,
}

impl rustler::Resource for ChildVmResource {}

static INSTANCE_COUNTER: AtomicU64 = AtomicU64::new(1);

fn generate_instance_id() -> u64 {
    INSTANCE_COUNTER.fetch_add(1, Ordering::SeqCst)
}

/// Create a new child VM instance
pub fn create_instance<'a>(
    env: Env<'a>,
    program_blob: Binary<'a>,
    initial_pc: Term<'a>,
    initial_gas: Term<'a>,
    initial_registers: Term<'a>,
) -> NifResult<Term<'a>> {
    // Decode parameters
    let pc: usize = usize::decode(initial_pc)?;
    let gas: u64 = u64::decode(initial_gas)?;
    let registers: Registers = Registers::decode(initial_registers)?;

    // Generate unique instance ID
    let instance_id = generate_instance_id();

    // Convert NIF registers to core registers
    let core_registers = CoreRegisters::from(registers);

    // Create child VM instance
    let instance = ChildVmInstance::new(
        instance_id,
        program_blob.as_slice(),
        pc,
        gas,
        core_registers,
    )
    .map_err(|_| rustler::Error::Term(Box::new(atoms::invalid_program())))?;

    // Wrap in resource
    let resource = ResourceArc::new(ChildVmResource {
        instance: Mutex::new(instance),
    });

    Ok((atoms::ok(), resource).encode(env))
}

pub fn execute<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    gas: Term<'a>,
    registers: Term<'a>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<ChildVmResource> = ResourceArc::decode(instance_ref)?;
    let mut instance = resource
        .instance
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new(atoms::mutex_poisoned())))?;

    let gas_value: u64 = u64::decode(gas)?;
    let registers_value: Registers = Registers::decode(registers)?;
    let core_registers = CoreRegisters::from(registers_value);

    let state = instance.get_state_mut();
    state.initial_gas = gas_value;
    state.spent_gas = 0;
    state.registers = core_registers;

    let result = instance.execute();
    let state = instance.get_state().clone();

    // Convert state to NIF-friendly format
    let vm_state = VmState::from(state);

    // Encode result
    let output = match result {
        ExecutionResult::Halt => atoms::halt().encode(env),
        ExecutionResult::OutOfGas => atoms::out_of_gas().encode(env),
        ExecutionResult::Panic => atoms::panic().encode(env),
        ExecutionResult::Fault { page } => (atoms::fault(), page).encode(env),
        ExecutionResult::HostCall { call_id } => (atoms::host_call(), call_id).encode(env),
    };

    Ok((output, vm_state).encode(env))
}

/// Read memory from child VM instance
pub fn read_memory<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    addr: Term<'a>,
    len: Term<'a>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<ChildVmResource> = ResourceArc::decode(instance_ref)?;
    let instance = resource
        .instance
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new(atoms::mutex_poisoned())))?;

    let address: usize = usize::decode(addr)?;
    let length: usize = usize::decode(len)?;

    match instance.read_memory(address, length) {
        Ok(data) => {
            let mut owned_binary = rustler::OwnedBinary::new(data.len()).unwrap();
            owned_binary.as_mut_slice().copy_from_slice(data);
            Ok((atoms::ok(), Binary::from_owned(owned_binary, env)).encode(env))
        }
        Err(_) => Ok((atoms::error(), atoms::oob()).encode(env)),
    }
}

/// Write memory to child VM instance
pub fn write_memory<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    addr: Term<'a>,
    data: Binary<'a>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<ChildVmResource> = ResourceArc::decode(instance_ref)?;
    let mut instance = resource
        .instance
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new(atoms::mutex_poisoned())))?;

    let address: usize = usize::decode(addr)?;

    match instance.write_memory(address, data.as_slice()) {
        Ok(()) => Ok(atoms::ok().encode(env)),
        Err(_) => Ok((atoms::error(), atoms::oob()).encode(env)),
    }
}

/// Get state from child VM instance
pub fn get_state<'a>(env: Env<'a>, instance_ref: Term<'a>) -> NifResult<Term<'a>> {
    let resource: ResourceArc<ChildVmResource> = ResourceArc::decode(instance_ref)?;
    let instance = resource
        .instance
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new(atoms::mutex_poisoned())))?;

    let state = instance.get_state().clone();
    let vm_state = VmState::from(state);

    Ok(vm_state.encode(env))
}

pub fn destroy<'a>(env: Env<'a>, _instance_ref: Term<'a>) -> NifResult<Term<'a>> {
    // The resource will be dropped when Elixir releases the reference
    Ok(atoms::ok().encode(env))
}

/// Set memory access permissions for a range of pages
/// permission: 0 = None, 1 = Read, 3 = ReadWrite
pub fn set_memory_access<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    page_index: Term<'a>,
    page_count: Term<'a>,
    permission: Term<'a>,
) -> NifResult<Term<'a>> {
    use pvm_core::Permission;

    let resource: ResourceArc<ChildVmResource> = ResourceArc::decode(instance_ref)?;
    let mut instance = resource
        .instance
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new(atoms::mutex_poisoned())))?;

    let page_idx: usize = usize::decode(page_index)?;
    let page_cnt: usize = usize::decode(page_count)?;
    let perm_val: u8 = u8::decode(permission)?;

    let perm = match perm_val {
        0 => Permission::None,
        1 => Permission::Read,
        3 => Permission::ReadWrite,
        _ => return Err(rustler::Error::BadArg),
    };

    match instance.set_memory_access(page_idx, page_cnt, perm) {
        Ok(()) => Ok(atoms::ok().encode(env)),
        Err(()) => Ok((atoms::error(), atoms::panic()).encode(env)),
    }
}

/// Check if pages have required access permissions
/// required_permission: 0 = None, 1 = Read, 3 = ReadWrite
/// Returns true if all pages have at least the required permission
pub fn check_memory_access<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    page_index: Term<'a>,
    page_count: Term<'a>,
    required_permission: Term<'a>,
) -> NifResult<Term<'a>> {
    use pvm_core::Permission;

    let resource: ResourceArc<ChildVmResource> = ResourceArc::decode(instance_ref)?;
    let instance = resource
        .instance
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new(atoms::mutex_poisoned())))?;

    let page_idx: usize = usize::decode(page_index)?;
    let page_cnt: usize = usize::decode(page_count)?;
    let perm_val: u8 = u8::decode(required_permission)?;

    let perm = match perm_val {
        0 => Permission::None,
        1 => Permission::Read,
        3 => Permission::ReadWrite,
        _ => return Err(rustler::Error::BadArg),
    };

    let has_access = instance.check_memory_access(page_idx, page_cnt, perm);
    Ok(has_access.encode(env))
}

/// Zero memory in an child VM instance
/// Efficiently zeros a range of memory without transferring data over NIF boundary
pub fn zero_memory<'a>(
    env: Env<'a>,
    instance_ref: Term<'a>,
    addr: Term<'a>,
    len: Term<'a>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<ChildVmResource> = ResourceArc::decode(instance_ref)?;
    let mut instance = resource
        .instance
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new(atoms::mutex_poisoned())))?;

    let address: usize = usize::decode(addr)?;
    let length: usize = usize::decode(len)?;

    match instance.zero_memory(address, length) {
        Ok(()) => Ok(atoms::ok().encode(env)),
        Err(_) => Ok((atoms::error(), atoms::oob()).encode(env)),
    }
}
