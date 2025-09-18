use rustler::{Atom, NifStruct, NifUntaggedEnum};

#[derive(Debug, Clone, NifUntaggedEnum)]
pub enum HostOutput {
    Bytes(Vec<u8>),
    Atom(Atom),
}

#[derive(Debug, Clone, NifStruct)]
#[module = "Pvm.Native.ExecuteResult"]
pub struct ExecuteResult {
    pub used_gas: u64,
    pub output: HostOutput,
}
