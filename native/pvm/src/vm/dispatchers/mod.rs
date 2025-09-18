pub mod no_args;
pub mod one_immediate;
pub mod reg_imm_offset;
pub mod reg_immediate;
pub mod reg_two_imm;
pub mod three_registers;
pub mod two_immediates;
pub mod two_registers;
pub mod two_registers_one_immediate;
pub mod two_registers_one_offset;
pub mod two_registers_two_immediates;

pub mod masks {
    pub const U8: u64 = 0xFF;
    pub const U16: u64 = 0xFFFF;
    pub const U32: u64 = 0xFFFF_FFFF;
}
