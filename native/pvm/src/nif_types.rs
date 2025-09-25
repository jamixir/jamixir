use crate::atoms;
use pvm_core::{ExecutionResult, Registers as CoreRegisters, VmState as CoreVmState};
use rustler::{Binary, Decoder, Encoder, Env, NifStruct, NifUntaggedEnum, OwnedBinary, Term};

#[derive(Clone, NifUntaggedEnum)]
pub enum HostOutput<'a> {
    Bytes(Binary<'a>),
    Atom(rustler::Atom),
}

#[derive(Clone, NifStruct)]
#[module = "Pvm.Native.ExecuteResult"]
pub struct ExecuteResult<'a> {
    pub used_gas: u64,
    pub output: HostOutput<'a>,
    pub context_token: u64,
}

impl<'a> ExecuteResult<'a> {
    pub fn is_waiting(&self) -> bool {
        matches!(self.output, HostOutput::Atom(a) if a == atoms::waiting())
    }

    pub fn from_core_result(
        env: Env<'a>,
        core_result: ExecutionResult,
        used_gas: u64,
        context_token: u64,
        output_bytes: Option<Vec<u8>>,
    ) -> Self {
        let output = match core_result {
            ExecutionResult::Halt => match output_bytes {
                Some(bytes) => {
                    let mut owned_binary = OwnedBinary::new(bytes.len()).unwrap();
                    owned_binary.as_mut_slice().copy_from_slice(&bytes);
                    HostOutput::Bytes(Binary::from_owned(owned_binary, env))
                }
                None => {
                    let owned_binary = OwnedBinary::new(0).unwrap();
                    HostOutput::Bytes(Binary::from_owned(owned_binary, env))
                }
            },
            ExecutionResult::Panic => HostOutput::Atom(atoms::panic()),
            ExecutionResult::OutOfGas => HostOutput::Atom(atoms::out_of_gas()),
            ExecutionResult::Fault { .. } => HostOutput::Atom(atoms::panic()),
            ExecutionResult::HostCall { .. } => HostOutput::Atom(atoms::waiting()),
        };

        ExecuteResult {
            used_gas,
            output,
            context_token,
        }
    }
}

#[derive(Debug, Clone, NifStruct, Copy)]
#[module = "Pvm.Native.VmState"]
pub struct VmState {
    pub registers: Registers,
    pub pc: usize,
    pub initial_gas: u64,
    pub spent_gas: u64,
}

impl From<CoreVmState> for VmState {
    fn from(core_state: CoreVmState) -> Self {
        VmState {
            registers: Registers::from(core_state.registers),
            pc: core_state.pc,
            initial_gas: core_state.initial_gas,
            spent_gas: core_state.spent_gas,
        }
    }
}

impl From<VmState> for CoreVmState {
    fn from(nif_state: VmState) -> Self {
        CoreVmState {
            registers: CoreRegisters::from(nif_state.registers),
            pc: nif_state.pc,
            initial_gas: nif_state.initial_gas,
            spent_gas: nif_state.spent_gas,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Registers {
    pub data: [u64; 13],
}

impl From<CoreRegisters> for Registers {
    fn from(core_regs: CoreRegisters) -> Self {
        Registers {
            data: core_regs.data,
        }
    }
}

impl From<Registers> for CoreRegisters {
    fn from(nif_regs: Registers) -> Self {
        CoreRegisters {
            data: nif_regs.data,
        }
    }
}

impl Decoder<'_> for Registers {
    fn decode(term: Term) -> rustler::NifResult<Self> {
        let list: Vec<u64> = term.decode()?;
        let mut data = [0u64; 13];
        for (i, &value) in list.iter().take(13).enumerate() {
            data[i] = value;
        }
        Ok(Registers { data })
    }
}

impl Encoder for Registers {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        self.data.to_vec().encode(env)
    }
}
