use rustler::{Binary, Encoder, Env, NifResult, OwnedBinary, OwnedEnv};

use crate::{
    atoms,
    core::{errors::ToNifResult, put_owned, Memory, MemoryRef, MemoryResource},
    types::host_result::{ExecuteResult, HostOutput},
    vm::{ExecutionResult, StepResult, VmContext, VmState},
};
use std::sync::Arc;

pub struct Vm {
    pub context: Arc<VmContext>,
    pub memory_ref: Option<MemoryRef>,
    pub memory: Option<Memory>,
    pub state: VmState,
    pub context_token: u64,
}

impl Vm {
    pub fn new(
        context: Arc<VmContext>,
        state: VmState,
        memory_ref: Option<MemoryRef>,
        memory: Option<Memory>,
        context_token: u64,
    ) -> Self {
        Self {
            context,
            memory_ref: Some(memory_ref.unwrap_or_else(|| MemoryResource::new_ref())),
            memory,
            state,
            context_token,
        }
    }

    pub fn test_instance(context: Arc<VmContext>, state: VmState, memory: Option<Memory>) -> Self {
        Self {
            context,
            memory_ref: None,
            memory,
            state,
            context_token: 0, // Test instances don't need real tokens
        }
    }

    pub fn execute(&mut self) -> ExecutionResult {
        loop {
            let exit_reason = self.single_step_run();

            match exit_reason {
                StepResult::Continue if self.state.has_gas() => {
                    continue;
                }
                _ => {
                    return ExecutionResult::from(exit_reason);
                }
            }
        }
    }

    pub fn arg_invoke<'a>(&mut self, env: Env<'a>) -> NifResult<ExecuteResult<'a>> {
        let result = self.execute();
        let used_gas = self.state.spent_gas;

        match result {
            ExecutionResult::Halt => {
                let start = self.state.registers.get(7) as usize;
                let len = self.state.registers.get(8) as usize;
                let output = match self
                    .memory
                    .as_ref()
                    .expect("Memory not available")
                    .read(start, len)
                {
                    Ok(bytes) => {
                        let mut owned_binary = OwnedBinary::new(bytes.len()).unwrap();
                        owned_binary.as_mut_slice().copy_from_slice(bytes);
                        HostOutput::Bytes(Binary::from_owned(owned_binary, env))
                    }
                    Err(_) => {
                        let owned_binary = OwnedBinary::new(0).unwrap();
                        HostOutput::Bytes(Binary::from_owned(owned_binary, env))
                    }
                };
                Ok(ExecuteResult {
                    used_gas,
                    output,
                    context_token: self.context_token,
                })
            }
            ExecutionResult::Panic { .. } => Ok(ExecuteResult {
                used_gas,
                output: HostOutput::Atom(atoms::panic()),
                context_token: self.context_token,
            }),
            ExecutionResult::OutOfGas { .. } => Ok(ExecuteResult {
                used_gas,
                output: HostOutput::Atom(atoms::out_of_gas()),
                context_token: self.context_token,
            }),
            ExecutionResult::Fault { .. } => Ok(ExecuteResult {
                used_gas,
                output: HostOutput::Atom(atoms::panic()),
                context_token: self.context_token,
            }),
            ExecutionResult::HostCall { call_id } => {
                let memory_ref = match &self.memory_ref {
                    Some(memory_ref) => memory_ref,
                    None => {
                        return Ok(ExecuteResult {
                            used_gas,
                            output: HostOutput::Atom(atoms::panic()),
                            context_token: self.context_token,
                        });
                    }
                };
                if let Some(memory) = self.memory.take() {
                    let _ = put_owned(memory_ref, memory).to_nif(env)?;
                }

                let pid = env.pid();
                let memory_ref = memory_ref.clone();
                let state = self.state.clone();
                let context_token = self.context_token;

                std::thread::spawn(move || {
                    let mut owned_env = OwnedEnv::new();

                    if let Err(e) = owned_env.send_and_clear(&pid, move |env| {
                        (atoms::ecall(), call_id, state, memory_ref, context_token).encode(env)
                    }) {
                        println!("ERROR: Failed to send ecall message: {:?}", e);
                    }
                });

                Ok(ExecuteResult {
                    used_gas,
                    output: HostOutput::Atom(atoms::waiting()),
                    context_token: self.context_token,
                })
            }
        }
    }
}
