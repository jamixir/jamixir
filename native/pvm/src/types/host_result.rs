use rustler::{Atom, Binary, NifStruct, NifUntaggedEnum};

#[derive(Clone, NifUntaggedEnum)]
pub enum HostOutput<'a> {
    Bytes(Binary<'a>),
    Atom(Atom),
}

#[derive(Clone, NifStruct)]
#[module = "Pvm.Native.ExecuteResult"]
pub struct ExecuteResult<'a> {
    pub used_gas: u64,
    pub output: HostOutput<'a>,
    pub context_token: u64,
}
