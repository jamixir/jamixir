use rustler::{Encoder, Env, NifResult, OwnedEnv};

use crate::{
    atoms,
    core::errors::ToNifResult,
    core::{put_owned, Memory, MemoryRef},
    types::host_result::{ExecuteResult, HostOutput},
    vm::{ExecutionResult, StepResult, VmContext, VmState},
};
use std::sync::Arc;

pub struct Vm {
    pub context: Arc<VmContext>,
    pub memory_ref: Option<MemoryRef>,
    pub memory: Option<Memory>,
    pub state: VmState,
}

impl Vm {
    pub fn new(
        context: Arc<VmContext>,
        state: VmState,
        memory_ref: MemoryRef,
        memory: Option<Memory>,
    ) -> Self {
        Self {
            context,
            memory_ref: Some(memory_ref),
            memory,
            state,
        }
    }

    pub fn test_instance(context: Arc<VmContext>, state: VmState, memory: Option<Memory>) -> Self {
        Self {
            context,
            memory_ref: None,
            memory,
            state,
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

    pub fn arg_invoke<'a>(&mut self, env: Env<'a>) -> NifResult<ExecuteResult> {
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
                    Ok(bytes) => HostOutput::Bytes(bytes.to_vec()),
                    Err(_) => HostOutput::Bytes(vec![]),
                };
                Ok(ExecuteResult { used_gas, output })
            }
            ExecutionResult::Panic { .. } => Ok(ExecuteResult {
                used_gas,
                output: HostOutput::Atom(atoms::panic()),
            }),
            ExecutionResult::OutOfGas { .. } => Ok(ExecuteResult {
                used_gas,
                output: HostOutput::Atom(atoms::out_of_gas()),
            }),
            ExecutionResult::Fault { .. } => Ok(ExecuteResult {
                used_gas,
                output: HostOutput::Atom(atoms::panic()),
            }),
            ExecutionResult::HostCall { call_id } => {
                let memory_ref = match &self.memory_ref {
                    Some(memory_ref) => memory_ref,
                    None => {
                        return Ok(ExecuteResult {
                            used_gas,
                            output: HostOutput::Atom(atoms::panic()),
                        });
                    }
                };
                if let Some(memory) = self.memory.take() {
                    let _ = put_owned(memory_ref, memory).to_nif()?;
                }

                // Send message to Elixir with VmState + memory_ref
                let pid = env.pid();
                let memory_ref = memory_ref.clone();
                let state = self.state.clone();

                std::thread::spawn(move || {
                    let mut owned_env = OwnedEnv::new();

                    if let Err(e) = owned_env.send_and_clear(&pid, move |env| {
                        (atoms::ecall(), call_id, state, memory_ref).encode(env)
                    }) {
                        println!("ERROR: Failed to send ecall message: {:?}", e);
                    }
                });

                Ok(ExecuteResult {
                    used_gas,
                    output: HostOutput::Atom(atoms::waiting()),
                })
            }
        }
    }
}
