pub mod atoms;
pub mod child_vm;
pub mod context;
pub mod execution;
pub mod memory;
pub mod nif_functions;
pub mod nif_types;

use crate::child_vm::ChildVmResource;
use crate::memory::MemoryResource;
use rustler::{Env, Term};

rustler::init!("Elixir.Pvm.Native", load = load);

fn load(env: Env, _info: Term) -> bool {
    env.register::<MemoryResource>().is_ok() && env.register::<ChildVmResource>().is_ok()
}
