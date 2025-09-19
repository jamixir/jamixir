pub const ZP: usize = 0x1000; // page size (4KB)
pub const ZZ: usize = 0x1_0000; // min allowed address (4KB)
pub const ZI: usize = 0x100_0000; // layout buffer size (16MB)
pub const MAX_ADDR: usize = 0x1_0000_0000; // 4GB

pub const PAGE_SIZE: usize = ZP;
pub const MIN_ADDR: usize = ZZ;
pub const MEMORY_SIZE: usize = MAX_ADDR;
pub const LAYOUT_BUFFER_SIZE: usize = ZI;

// Access control: 2 bits per page, 32 pages per 64-bit word
pub const PAGES_PER_ACCESS_WORD: usize = 32;

pub const GAS_COST: u64 = 1;

pub const TERMINATION_INSTRUCTIONS: [bool; 231] = {
    let mut arr = [false; 231];

    // Trap and fallthrough
    arr[0] = true; // trap
    arr[1] = true; // fallthrough

    // Jumps
    arr[40] = true; // jump
    arr[50] = true; // jump_ind

    // Load-and-jumps
    arr[80] = true; // load_imm_jump
    arr[180] = true; // load_imm_jump_ind

    // Branches
    arr[170] = true; // branch_eq
    arr[171] = true; // branch_ne
    arr[172] = true; // branch_lt_u
    arr[173] = true; // branch_lt_s
    arr[174] = true; // branch_ge_u
    arr[175] = true; // branch_ge_s

    arr[81] = true; // branch_eq_imm
    arr[82] = true; // branch_ne_imm
    arr[83] = true; // branch_lt_u_imm
    arr[87] = true; // branch_lt_s_imm
    arr[84] = true; // branch_le_u_imm
    arr[88] = true; // branch_le_s_imm
    arr[85] = true; // branch_ge_u_imm
    arr[89] = true; // branch_ge_s_imm
    arr[86] = true; // branch_gt_u_imm
    arr[90] = true; // branch_gt_s_imm

    arr
};

pub fn is_termination_instruction(opcode: u8) -> bool {
    unsafe { *TERMINATION_INSTRUCTIONS.get_unchecked(opcode as usize) }
}
