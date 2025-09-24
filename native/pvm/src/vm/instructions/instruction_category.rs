use super::opcodes::*;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum InstructionCategory {
    NoArgs,
    OneImmediate,
    TwoImmediates,
    RegImmediate,
    RegTwoImm,
    RegImmediateOffset,
    TwoRegisters,
    TwoRegistersOneImmediate,
    TwoRegistersOneOffset,
    TwoRegistersTwoImmediates,
    ThreeRegisters,
    Unknown,
}

static OPCODE_CATEGORY: [InstructionCategory; 256] = {
    let mut table = [InstructionCategory::Unknown; 256];

    // No args instructions
    table[TRAP as usize] = InstructionCategory::NoArgs;
    table[FALLTHROUGH as usize] = InstructionCategory::NoArgs;

    // One immediate instructions
    table[ECALLI as usize] = InstructionCategory::OneImmediate;
    table[JUMP as usize] = InstructionCategory::OneImmediate;

    // Two immediates instructions
    table[STORE_IMM_U8 as usize] = InstructionCategory::TwoImmediates;
    table[STORE_IMM_U16 as usize] = InstructionCategory::TwoImmediates;
    table[STORE_IMM_U32 as usize] = InstructionCategory::TwoImmediates;
    table[STORE_IMM_U64 as usize] = InstructionCategory::TwoImmediates;

    // Register + immediate instructions
    table[LOAD_IMM_64 as usize] = InstructionCategory::RegImmediate;
    table[JUMP_IND as usize] = InstructionCategory::RegImmediate;
    table[LOAD_IMM as usize] = InstructionCategory::RegImmediate;
    table[LOAD_U8 as usize] = InstructionCategory::RegImmediate;
    table[LOAD_I8 as usize] = InstructionCategory::RegImmediate;
    table[LOAD_U16 as usize] = InstructionCategory::RegImmediate;
    table[LOAD_I16 as usize] = InstructionCategory::RegImmediate;
    table[LOAD_U32 as usize] = InstructionCategory::RegImmediate;
    table[LOAD_I32 as usize] = InstructionCategory::RegImmediate;
    table[LOAD_U64 as usize] = InstructionCategory::RegImmediate;
    table[STORE_U8 as usize] = InstructionCategory::RegImmediate;
    table[STORE_U16 as usize] = InstructionCategory::RegImmediate;
    table[STORE_U32 as usize] = InstructionCategory::RegImmediate;
    table[STORE_U64 as usize] = InstructionCategory::RegImmediate;

    // Register + two immediates instructions
    table[STORE_IMM_IND_U8 as usize] = InstructionCategory::RegTwoImm;
    table[STORE_IMM_IND_U16 as usize] = InstructionCategory::RegTwoImm;
    table[STORE_IMM_IND_U32 as usize] = InstructionCategory::RegTwoImm;
    table[STORE_IMM_IND_U64 as usize] = InstructionCategory::RegTwoImm;

    // Register + immediate + offset instructions
    table[LOAD_IMM_JUMP as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_EQ_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_NE_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_LT_U_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_LE_U_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_GE_U_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_GT_U_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_LT_S_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_LE_S_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_GE_S_IMM as usize] = InstructionCategory::RegImmediateOffset;
    table[BRANCH_GT_S_IMM as usize] = InstructionCategory::RegImmediateOffset;

    // Two registers instructions
    table[MOVE_REG as usize] = InstructionCategory::TwoRegisters;
    table[SBRK as usize] = InstructionCategory::TwoRegisters;
    table[COUNT_SET_BITS_64 as usize] = InstructionCategory::TwoRegisters;
    table[COUNT_SET_BITS_32 as usize] = InstructionCategory::TwoRegisters;
    table[LEADING_ZERO_BITS_64 as usize] = InstructionCategory::TwoRegisters;
    table[LEADING_ZERO_BITS_32 as usize] = InstructionCategory::TwoRegisters;
    table[TRAILING_ZERO_BITS_64 as usize] = InstructionCategory::TwoRegisters;
    table[TRAILING_ZERO_BITS_32 as usize] = InstructionCategory::TwoRegisters;
    table[SIGN_EXTEND_8 as usize] = InstructionCategory::TwoRegisters;
    table[SIGN_EXTEND_16 as usize] = InstructionCategory::TwoRegisters;
    table[ZERO_EXTEND_16 as usize] = InstructionCategory::TwoRegisters;
    table[REVERSE_BYTES as usize] = InstructionCategory::TwoRegisters;

    // Two registers + one immediate instructions
    table[STORE_IND_U8 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[STORE_IND_U16 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[STORE_IND_U32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[STORE_IND_U64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[LOAD_IND_U8 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[LOAD_IND_I8 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[LOAD_IND_U16 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[LOAD_IND_I16 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[LOAD_IND_U32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[LOAD_IND_I32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[LOAD_IND_U64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[ADD_IMM_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[AND_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[XOR_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[OR_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[MUL_IMM_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SET_LT_U_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SET_LT_S_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_L_IMM_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_R_IMM_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHAR_R_IMM_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[NEG_ADD_IMM_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SET_GT_U_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SET_GT_S_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_L_IMM_ALT_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_R_IMM_ALT_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHAR_R_IMM_ALT_32 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[CMOV_IZ_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[CMOV_NZ_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[ADD_IMM_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[MUL_IMM_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_L_IMM_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_R_IMM_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHAR_R_IMM_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[NEG_ADD_IMM_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_L_IMM_ALT_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHLO_R_IMM_ALT_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[SHAR_R_IMM_ALT_64 as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[ROT_R_64_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[ROT_R_64_IMM_ALT as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[ROT_R_32_IMM as usize] = InstructionCategory::TwoRegistersOneImmediate;
    table[ROT_R_32_IMM_ALT as usize] = InstructionCategory::TwoRegistersOneImmediate;

    // Two registers + one offset instructions
    table[BRANCH_EQ as usize] = InstructionCategory::TwoRegistersOneOffset;
    table[BRANCH_NE as usize] = InstructionCategory::TwoRegistersOneOffset;
    table[BRANCH_LT_U as usize] = InstructionCategory::TwoRegistersOneOffset;
    table[BRANCH_LT_S as usize] = InstructionCategory::TwoRegistersOneOffset;
    table[BRANCH_GE_U as usize] = InstructionCategory::TwoRegistersOneOffset;
    table[BRANCH_GE_S as usize] = InstructionCategory::TwoRegistersOneOffset;

    // Two registers + two immediates instructions
    table[LOAD_IMM_JUMP_IND as usize] = InstructionCategory::TwoRegistersTwoImmediates;

    // Three registers instructions
    table[ADD_32 as usize] = InstructionCategory::ThreeRegisters;
    table[SUB_32 as usize] = InstructionCategory::ThreeRegisters;
    table[MUL_32 as usize] = InstructionCategory::ThreeRegisters;
    table[DIV_U_32 as usize] = InstructionCategory::ThreeRegisters;
    table[DIV_S_32 as usize] = InstructionCategory::ThreeRegisters;
    table[REM_U_32 as usize] = InstructionCategory::ThreeRegisters;
    table[REM_S_32 as usize] = InstructionCategory::ThreeRegisters;
    table[SHLO_L_32 as usize] = InstructionCategory::ThreeRegisters;
    table[SHLO_R_32 as usize] = InstructionCategory::ThreeRegisters;
    table[SHAR_R_32 as usize] = InstructionCategory::ThreeRegisters;
    table[ADD_64 as usize] = InstructionCategory::ThreeRegisters;
    table[SUB_64 as usize] = InstructionCategory::ThreeRegisters;
    table[MUL_64 as usize] = InstructionCategory::ThreeRegisters;
    table[DIV_U_64 as usize] = InstructionCategory::ThreeRegisters;
    table[DIV_S_64 as usize] = InstructionCategory::ThreeRegisters;
    table[REM_U_64 as usize] = InstructionCategory::ThreeRegisters;
    table[REM_S_64 as usize] = InstructionCategory::ThreeRegisters;
    table[SHLO_L_64 as usize] = InstructionCategory::ThreeRegisters;
    table[SHLO_R_64 as usize] = InstructionCategory::ThreeRegisters;
    table[SHAR_R_64 as usize] = InstructionCategory::ThreeRegisters;
    table[AND as usize] = InstructionCategory::ThreeRegisters;
    table[XOR as usize] = InstructionCategory::ThreeRegisters;
    table[OR as usize] = InstructionCategory::ThreeRegisters;
    table[MUL_UPPER_S_S as usize] = InstructionCategory::ThreeRegisters;
    table[MUL_UPPER_U_U as usize] = InstructionCategory::ThreeRegisters;
    table[MUL_UPPER_S_U as usize] = InstructionCategory::ThreeRegisters;
    table[SET_LT_U as usize] = InstructionCategory::ThreeRegisters;
    table[SET_LT_S as usize] = InstructionCategory::ThreeRegisters;
    table[CMOV_IZ as usize] = InstructionCategory::ThreeRegisters;
    table[CMOV_NZ as usize] = InstructionCategory::ThreeRegisters;
    table[ROT_L_64 as usize] = InstructionCategory::ThreeRegisters;
    table[ROT_L_32 as usize] = InstructionCategory::ThreeRegisters;
    table[ROT_R_64 as usize] = InstructionCategory::ThreeRegisters;
    table[ROT_R_32 as usize] = InstructionCategory::ThreeRegisters;
    table[AND_INV as usize] = InstructionCategory::ThreeRegisters;
    table[OR_INV as usize] = InstructionCategory::ThreeRegisters;
    table[XNOR as usize] = InstructionCategory::ThreeRegisters;
    table[MAX as usize] = InstructionCategory::ThreeRegisters;
    table[MAX_U as usize] = InstructionCategory::ThreeRegisters;
    table[MIN as usize] = InstructionCategory::ThreeRegisters;
    table[MIN_U as usize] = InstructionCategory::ThreeRegisters;

    table
};

/// Get instruction category for an opcode - O(1) lookup
#[inline(always)]
pub fn get_category(opcode: u8) -> InstructionCategory {
    unsafe { *OPCODE_CATEGORY.get_unchecked(opcode as usize) }
}
