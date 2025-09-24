use rustler::{Encoder, Env, NifResult};

use crate::{
    atoms,
    core::memory::{FaultError, MemoryError, MutexError},
};

macro_rules! to_rustler_error {
    ($atom:expr) => {
        rustler::Error::Term(Box::new($atom))
    };
    ($struct_name:ident { $($field:ident: $value:expr),* $(,)? }) => {
        rustler::Error::Term(Box::new($struct_name {
            $($field: $value),*
        }))
    };
}

pub trait ToNifResult<T> {
    fn to_nif(self, env: Env) -> NifResult<(rustler::Atom, rustler::Term)>;
}

impl<T: Encoder> ToNifResult<T> for Result<T, MemoryError> {
    fn to_nif(self, env: Env) -> NifResult<(rustler::Atom, rustler::Term)> {
        match self {
            Ok(val) => Ok((atoms::ok(), val.encode(env))),
            Err(MemoryError::Fault { page_addr }) => {
                let fault_error = FaultError {
                    fault: atoms::fault(),
                    page_addr,
                };
                Ok((atoms::error(), fault_error.encode(env)))
            }
            Err(MemoryError::Panic) => Ok((atoms::error(), atoms::panic().encode(env))),
        }
    }
}

impl<T: Encoder> ToNifResult<T> for Result<T, MutexError> {
    fn to_nif(self, env: Env) -> NifResult<(rustler::Atom, rustler::Term)> {
        match self {
            Ok(val) => Ok((atoms::ok(), val.encode(env))),
            Err(MutexError::Poisoned) => Ok((atoms::error(), atoms::mutex_poisoned().encode(env))),
            Err(MutexError::MemoryAlreadyPresent) => {
                Ok((atoms::error(), atoms::memory_already_present().encode(env)))
            }
        }
    }
}

pub(crate) use to_rustler_error;
