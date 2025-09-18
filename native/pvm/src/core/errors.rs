use rustler::NifResult;

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
    fn to_nif(self) -> NifResult<T>;
}

impl<T> ToNifResult<T> for Result<T, MemoryError> {
    fn to_nif(self) -> NifResult<T> {
        match self {
            Ok(val) => Ok(val),
            Err(MemoryError::Fault { page_addr }) => Err(to_rustler_error!(FaultError {
                fault: atoms::fault(),
                page_addr,
            })),
            Err(MemoryError::Panic) => Err(to_rustler_error!(atoms::panic())),
        }
    }
}

impl<T> ToNifResult<T> for Result<T, MutexError> {
    fn to_nif(self) -> NifResult<T> {
        match self {
            Ok(val) => Ok(val),
            Err(MutexError::Poisoned) => Err(to_rustler_error!(atoms::mutex_poisoned())),
            Err(MutexError::MemoryAlreadyPresent) => {
                Err(to_rustler_error!(atoms::memory_already_present()))
            }
        }
    }
}

pub(crate) use to_rustler_error;
