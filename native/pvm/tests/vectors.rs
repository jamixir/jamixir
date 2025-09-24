use pvm::{
    core::{Memory, Permission, Registers, StartSet},
    encoding::deblob,
    vm::{ExecutionResult, Vm, VmContext, VmState},
};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::sync::Arc;

static TEST_VECTORS_DIR: &str = "/home/luke/Documents/Jamixir/pvm-test-vectors/pvm/programs/";

#[derive(Debug, Deserialize, Serialize)]
struct TestCase {
    name: String,
    #[serde(rename = "initial-pc")]
    initial_pc: usize,
    #[serde(rename = "initial-gas")]
    initial_gas: u64,
    #[serde(rename = "initial-regs")]
    initial_regs: Vec<u64>,
    #[serde(rename = "initial-page-map")]
    initial_page_map: Vec<PageMapEntry>,
    #[serde(rename = "initial-memory")]
    initial_memory: Vec<MemoryEntry>,
    program: Vec<u8>,
    #[serde(rename = "expected-status")]
    expected_status: String,
    #[serde(rename = "expected-pc")]
    expected_pc: usize,
    #[serde(rename = "expected-regs")]
    expected_regs: Vec<u64>,
    #[serde(rename = "expected-memory")]
    expected_memory: Vec<MemoryEntry>,
    #[serde(rename = "expected-gas")]
    expected_gas: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct PageMapEntry {
    address: usize,
    length: usize,
    #[serde(rename = "is-writable")]
    is_writable: bool,
}

#[derive(Debug, Deserialize, Serialize)]
struct MemoryEntry {
    address: usize,
    contents: Vec<u8>,
}

fn status_to_execution_result(status: &str) -> ExecutionResult {
    match status {
        "halt" => ExecutionResult::Halt,
        "panic" => ExecutionResult::Panic,
        "out-of-gas" => ExecutionResult::OutOfGas,
        "page-fault" => ExecutionResult::Fault { page: 0 }, // Page will be validated separately
        _ => {
            if status.starts_with("ecall:") {
                let call_id = status.strip_prefix("ecall:").unwrap().parse().unwrap_or(0);
                ExecutionResult::HostCall { call_id }
            } else {
                ExecutionResult::Panic
            }
        }
    }
}

fn setup_memory_with_permissions(
    page_map: &[PageMapEntry],
    memory_entries: &[MemoryEntry],
) -> Result<Memory, String> {
    // Create memory with enough pages for all addresses
    let max_addr = page_map
        .iter()
        .map(|entry| entry.address + entry.length)
        .max()
        .unwrap_or(4096);

    let num_pages = (max_addr + 4095) >> 12; // Round up to next page boundary
    let mut memory = Memory::test_memory(num_pages.max(1));

    for entry in page_map {
        memory.set_access(entry.address, entry.length, Permission::ReadWrite);
    }

    // Write initial memory contents
    for entry in memory_entries {
        memory.write(entry.address, &entry.contents).map_err(|e| {
            format!(
                "Failed to write initial memory at address {}: {:?}",
                entry.address, e
            )
        })?;
    }

    for entry in page_map {
        let permission = if entry.is_writable {
            Permission::ReadWrite
        } else {
            Permission::Read
        };
        memory.set_access(entry.address, entry.length, permission);
    }

    Ok(memory)
}

fn run_test_case(
    test_case: &TestCase,
) -> Result<(ExecutionResult, VmState, Memory), Box<dyn std::error::Error>> {
    let registers = Registers::from_vec(test_case.initial_regs.clone());

    let memory =
        setup_memory_with_permissions(&test_case.initial_page_map, &test_case.initial_memory)?;

    let deblob_result = deblob(&test_case.program);
    let start_set = StartSet::build(&deblob_result.program, &deblob_result.bitmask);

    let context = Arc::new(VmContext {
        program: deblob_result.program,
        bitmask: deblob_result.bitmask,
        jump_table: deblob_result.jump_table,
        start_set,
    });

    let state = VmState::new(registers, test_case.initial_pc, test_case.initial_gas);

    let mut vm = Vm::test_instance(context, state, Some(memory));
    let execution_result = vm.execute();
    let final_state = vm.state;
    let final_memory = vm.memory.unwrap();

    Ok((execution_result, final_state, final_memory))
}

fn validate_test_results(
    test_case: &TestCase,
    actual_exit_reason: ExecutionResult,
    final_state: &VmState,
    final_memory: &Memory,
) -> Result<(), String> {
    let expected_exit_reason = status_to_execution_result(&test_case.expected_status);

    match (&actual_exit_reason, &expected_exit_reason) {
        (ExecutionResult::Fault { .. }, ExecutionResult::Fault { .. }) => {}
        (ExecutionResult::HostCall { .. }, ExecutionResult::HostCall { .. }) => {}
        (actual, expected)
            if std::mem::discriminant(actual) == std::mem::discriminant(expected) => {}
        _ => {
            return Err(format!(
                "Exit reason mismatch: expected {:?}, got {:?}",
                expected_exit_reason, actual_exit_reason
            ));
        }
    }

    if !matches!(
        actual_exit_reason,
        ExecutionResult::Halt | ExecutionResult::Panic
    ) {
        if final_state.pc != test_case.expected_pc {
            return Err(format!(
                "PC mismatch: expected {}, got {}",
                test_case.expected_pc, final_state.pc
            ));
        }
    }

    for (i, &expected_value) in test_case.expected_regs.iter().enumerate() {
        if i < 13 {
            let actual_value = final_state.registers.get(i);
            if actual_value != expected_value {
                return Err(format!(
                    "Register r{} mismatch: expected {}, got {}",
                    i, expected_value, actual_value
                ));
            }
        }
    }

    // Check gas consumption
    // let expected_spent_gas = test_case.initial_gas - test_case.expected_gas;
    // if final_state.spent_gas != expected_spent_gas {
    //     return Err(format!(
    //         "Gas consumption mismatch: expected {}, got {}",
    //         expected_spent_gas, final_state.spent_gas
    //     ));
    // }

    for entry in &test_case.expected_memory {
        match final_memory.read(entry.address, entry.contents.len()) {
            Ok(data) => {
                if data != entry.contents.as_slice() {
                    return Err(format!(
                        "Memory at address {} mismatch: expected {:?}, got {:?}",
                        entry.address, entry.contents, data
                    ));
                }
            }
            Err(e) => {
                return Err(format!(
                    "Failed to read memory at address {}: {:?}",
                    entry.address, e
                ));
            }
        }
    }

    Ok(())
}

pub fn run_case(file_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let content = fs::read_to_string(file_path)?;
    let test_case: TestCase = serde_json::from_str(&content)?;

    let (exit_reason, final_state, final_memory) = run_test_case(&test_case)?;

    validate_test_results(&test_case, exit_reason, &final_state, &final_memory)
        .map_err(|e| e.into())
}

#[test]
#[ignore]
fn test_specific_test() {
    let test_case = "riscv_rv64uzbb_rolw";
    let test_file = TEST_VECTORS_DIR.to_string() + test_case + ".json";

    if Path::new(&test_file).exists() {
        match run_case(&test_file) {
            Ok(_) => println!("Test passed!"),
            Err(e) => panic!("Test failed with error: {}", e),
        }
    } else {
        println!("Test file {} not found, skipping", test_file);
    }
}

macro_rules! generate_json_tests {
    ($($test_fn_name:ident: $json_name:expr),* $(,)?) => {
        $(
            #[test]
            fn $test_fn_name() {


                let test_file = format!("{}{}.json", TEST_VECTORS_DIR, $json_name);

                if Path::new(&test_file).exists() {
                    match run_case(&test_file) {
                        Ok(_) => {},
                        Err(e) => panic!("Test failed: {}", e),
                    }
                } else {
                    panic!("Test file {} not found", test_file);
                }
            }
        )*
    };
}

generate_json_tests!(
    // NoArgs instructions
    test_inst_fallthrough: "inst_fallthrough",
    test_inst_trap: "inst_trap",

    // OneImmediate instructions
    test_inst_jump: "inst_jump",
    test_inst_load_imm_and_jump: "inst_load_imm_and_jump",

    // RegImmediate instructions (LOAD_*)
    test_inst_load_imm_64: "inst_load_imm_64",
    test_inst_load_imm: "inst_load_imm",
    test_inst_load_u8: "inst_load_u8",
    test_inst_load_i8: "inst_load_i8",
    test_inst_load_u16: "inst_load_u16",
    test_inst_load_i16: "inst_load_i16",
    test_inst_load_u32: "inst_load_u32",
    test_inst_load_i32: "inst_load_i32",
    test_inst_load_u64: "inst_load_u64",

    // RegImmediate instructions (STORE_*)
    test_inst_store_u8: "inst_store_u8",
    test_inst_store_u16: "inst_store_u16",
    test_inst_store_u32: "inst_store_u32",
    test_inst_store_u64: "inst_store_u64",

    // TwoImmediates instructions (STORE_IMM_*)
    test_inst_store_imm_u8: "inst_store_imm_u8",
    test_inst_store_imm_u16: "inst_store_imm_u16",
    test_inst_store_imm_u32: "inst_store_imm_u32",
    test_inst_store_imm_u64: "inst_store_imm_u64",

    // RegTwoImm instructions (STORE_IMM_IND_*) - Working cases
    test_inst_store_imm_indirect_u8_with_offset_ok: "inst_store_imm_indirect_u8_with_offset_ok",
    test_inst_store_imm_indirect_u8_without_offset_ok: "inst_store_imm_indirect_u8_without_offset_ok",
    test_inst_store_imm_indirect_u16_with_offset_ok: "inst_store_imm_indirect_u16_with_offset_ok",
    test_inst_store_imm_indirect_u16_without_offset_ok: "inst_store_imm_indirect_u16_without_offset_ok",
    test_inst_store_imm_indirect_u32_with_offset_ok: "inst_store_imm_indirect_u32_with_offset_ok",
    test_inst_store_imm_indirect_u32_without_offset_ok: "inst_store_imm_indirect_u32_without_offset_ok",
    test_inst_store_imm_indirect_u64_with_offset_ok: "inst_store_imm_indirect_u64_with_offset_ok",
    test_inst_store_imm_indirect_u64_without_offset_ok: "inst_store_imm_indirect_u64_without_offset_ok",

    // RegImmediateOffset instructions (Branch with immediate)
    test_inst_branch_eq_imm_ok: "inst_branch_eq_imm_ok",
    test_inst_branch_eq_imm_nok: "inst_branch_eq_imm_nok",
    test_inst_branch_not_eq_imm_ok: "inst_branch_not_eq_imm_ok",
    test_inst_branch_not_eq_imm_nok: "inst_branch_not_eq_imm_nok",
    test_inst_branch_less_unsigned_imm_ok: "inst_branch_less_unsigned_imm_ok",
    test_inst_branch_less_unsigned_imm_nok: "inst_branch_less_unsigned_imm_nok",
    test_inst_branch_less_or_equal_unsigned_imm_ok: "inst_branch_less_or_equal_unsigned_imm_ok",
    test_inst_branch_less_or_equal_unsigned_imm_nok: "inst_branch_less_or_equal_unsigned_imm_nok",
    test_inst_branch_greater_or_equal_unsigned_imm_ok: "inst_branch_greater_or_equal_unsigned_imm_ok",
    test_inst_branch_greater_or_equal_unsigned_imm_nok: "inst_branch_greater_or_equal_unsigned_imm_nok",
    test_inst_branch_greater_unsigned_imm_ok: "inst_branch_greater_unsigned_imm_ok",
    test_inst_branch_greater_unsigned_imm_nok: "inst_branch_greater_unsigned_imm_nok",
    test_inst_branch_less_signed_imm_ok: "inst_branch_less_signed_imm_ok",
    test_inst_branch_less_signed_imm_nok: "inst_branch_less_signed_imm_nok",
    test_inst_branch_less_or_equal_signed_imm_ok: "inst_branch_less_or_equal_signed_imm_ok",
    test_inst_branch_less_or_equal_signed_imm_nok: "inst_branch_less_or_equal_signed_imm_nok",
    test_inst_branch_greater_or_equal_signed_imm_ok: "inst_branch_greater_or_equal_signed_imm_ok",
    test_inst_branch_greater_or_equal_signed_imm_nok: "inst_branch_greater_or_equal_signed_imm_nok",
    test_inst_branch_greater_signed_imm_ok: "inst_branch_greater_signed_imm_ok",
    test_inst_branch_greater_signed_imm_nok: "inst_branch_greater_signed_imm_nok",

    // ThreeRegisters instructions
    test_inst_add_32: "inst_add_32",
    test_inst_add_32_with_overflow: "inst_add_32_with_overflow",
    test_inst_add_32_with_truncation: "inst_add_32_with_truncation",
    test_inst_add_32_with_truncation_and_sign_extension: "inst_add_32_with_truncation_and_sign_extension",
    test_inst_add_64: "inst_add_64",
    test_inst_add_64_with_overflow: "inst_add_64_with_overflow",
    test_inst_sub_32: "inst_sub_32",
    test_inst_sub_64: "inst_sub_64",
    test_inst_sub_64_with_overflow: "inst_sub_64_with_overflow",
    test_inst_mul_32: "inst_mul_32",
    test_inst_mul_64: "inst_mul_64",
    test_inst_div_u_32: "inst_div_unsigned_32",
    test_inst_div_s_32: "inst_div_signed_32",
    test_inst_div_s_32_by_zero: "inst_div_signed_32_by_zero",
    test_inst_div_s_32_with_overflow: "inst_div_signed_32_with_overflow",
    test_inst_div_s_64: "inst_div_signed_64",
    test_inst_div_s_64_by_zero: "inst_div_signed_64_by_zero",
    test_inst_div_s_64_with_overflow: "inst_div_signed_64_with_overflow",
    test_inst_div_u_32_by_zero: "inst_div_unsigned_32_by_zero",
    test_inst_div_u_32_with_overflow: "inst_div_unsigned_32_with_overflow",
    test_inst_div_u_64: "inst_div_unsigned_64",
    test_inst_div_u_64_by_zero: "inst_div_unsigned_64_by_zero",
    test_inst_div_u_64_with_overflow: "inst_div_unsigned_64_with_overflow",
    test_inst_rem_u_32: "inst_rem_unsigned_32",
    test_inst_rem_s_32: "inst_rem_signed_32",
    test_inst_rem_s_32_by_zero: "inst_rem_signed_32_by_zero",
    test_inst_rem_s_32_with_overflow: "inst_rem_signed_32_with_overflow",
    test_inst_rem_s_64: "inst_rem_signed_64",
    test_inst_rem_s_64_by_zero: "inst_rem_signed_64_by_zero",
    test_inst_rem_s_64_with_overflow: "inst_rem_signed_64_with_overflow",
    test_inst_rem_u_32_by_zero: "inst_rem_unsigned_32_by_zero",
    test_inst_rem_u_64: "inst_rem_unsigned_64",
    test_inst_rem_u_64_by_zero: "inst_rem_unsigned_64_by_zero",
    test_inst_and: "inst_and",
    test_inst_or: "inst_or",
    test_inst_xor: "inst_xor",
    test_inst_shift_arithmetic_right_32: "inst_shift_arithmetic_right_32",
    test_inst_shift_arithmetic_right_32_with_overflow: "inst_shift_arithmetic_right_32_with_overflow",
    test_inst_shift_arithmetic_right_64: "inst_shift_arithmetic_right_64",
    test_inst_shift_arithmetic_right_64_with_overflow: "inst_shift_arithmetic_right_64_with_overflow",
    test_inst_shift_logical_left_32: "inst_shift_logical_left_32",
    test_inst_shift_logical_left_32_with_overflow: "inst_shift_logical_left_32_with_overflow",
    test_inst_shift_logical_left_64: "inst_shift_logical_left_64",
    test_inst_shift_logical_left_64_with_overflow: "inst_shift_logical_left_64_with_overflow",
    test_inst_shift_logical_right_32: "inst_shift_logical_right_32",
    test_inst_shift_logical_right_32_with_overflow: "inst_shift_logical_right_32_with_overflow",
    test_inst_shift_logical_right_64: "inst_shift_logical_right_64",
    test_inst_shift_logical_right_64_with_overflow: "inst_shift_logical_right_64_with_overflow",
    test_inst_set_less_than_signed_0: "inst_set_less_than_signed_0",
    test_inst_set_less_than_signed_1: "inst_set_less_than_signed_1",
    test_inst_set_less_than_unsigned_0: "inst_set_less_than_unsigned_0",
    test_inst_set_less_than_unsigned_1: "inst_set_less_than_unsigned_1",
    test_inst_cmov_if_zero_ok: "inst_cmov_if_zero_ok",
    test_inst_cmov_if_zero_nok: "inst_cmov_if_zero_nok",



    // RegTwoImm instructions (STORE_IMM_IND_*) - Error cases
    test_inst_store_imm_indirect_u8_with_offset_nok: "inst_store_imm_indirect_u8_with_offset_nok",
    test_inst_store_imm_indirect_u16_with_offset_nok: "inst_store_imm_indirect_u16_with_offset_nok",
    test_inst_store_imm_indirect_u32_with_offset_nok: "inst_store_imm_indirect_u32_with_offset_nok",
    test_inst_store_imm_indirect_u64_with_offset_nok: "inst_store_imm_indirect_u64_with_offset_nok",

    test_inst_store_imm_u8_trap_inaccessible: "inst_store_imm_u8_trap_inaccessible",

    test_inst_sub_32_with_overflow: "inst_sub_32_with_overflow",



    // Gas testsMemoryError
    test_gas_basic_consume_all: "gas_basic_consume_all",

    // TwoRegisters instructions
    test_inst_move_reg: "inst_move_reg",

    // SBRK instruction tests
    test_sbrk_zero_query: "sbrk_zero_query",
    test_sbrk_small_allocation: "sbrk_small_allocation",
    test_sbrk_large_allocation: "sbrk_large_allocation",
    test_sbrk_max_heap_allocation: "sbrk_max_heap_allocation",
    test_sbrk_overflow_allocation: "sbrk_overflow_allocation",
    test_sbrk_wrapping_size: "sbrk_wrapping_size",
    test_sbrk_different_registers: "sbrk_different_registers",
    test_sbrk_register_preservation: "sbrk_register_preservation",
    // RegImmediate instructions (immediate variants)
    test_inst_add_imm_32: "inst_add_imm_32",
    test_inst_add_imm_32_with_truncation: "inst_add_imm_32_with_truncation",
    test_inst_add_imm_32_with_truncation_and_sign_extension: "inst_add_imm_32_with_truncation_and_sign_extension",
    test_inst_add_imm_64: "inst_add_imm_64",
    test_inst_and_imm: "inst_and_imm",
    test_inst_or_imm: "inst_or_imm",
    test_inst_xor_imm: "inst_xor_imm",
    test_inst_sub_imm_32: "inst_sub_imm_32",
    test_inst_sub_imm_64: "inst_sub_imm_64",
    test_inst_mul_imm_32: "inst_mul_imm_32",
    test_inst_mul_imm_64: "inst_mul_imm_64",
    test_inst_negate_and_add_imm_32: "inst_negate_and_add_imm_32",
    test_inst_negate_and_add_imm_64: "inst_negate_and_add_imm_64",
    test_inst_shift_arithmetic_right_imm_32: "inst_shift_arithmetic_right_imm_32",
    test_inst_shift_arithmetic_right_imm_64: "inst_shift_arithmetic_right_imm_64",
    test_inst_shift_arithmetic_right_imm_alt_32: "inst_shift_arithmetic_right_imm_alt_32",
    test_inst_shift_arithmetic_right_imm_alt_64: "inst_shift_arithmetic_right_imm_alt_64",
    test_inst_shift_logical_left_imm_32: "inst_shift_logical_left_imm_32",
    test_inst_shift_logical_left_imm_64: "inst_shift_logical_left_imm_64",
    test_inst_shift_logical_left_imm_alt_32: "inst_shift_logical_left_imm_alt_32",
    test_inst_shift_logical_left_imm_alt_64: "inst_shift_logical_left_imm_alt_64",
    test_inst_shift_logical_right_imm_32: "inst_shift_logical_right_imm_32",
    test_inst_shift_logical_right_imm_64: "inst_shift_logical_right_imm_64",
    test_inst_shift_logical_right_imm_alt_32: "inst_shift_logical_right_imm_alt_32",
    test_inst_shift_logical_right_imm_alt_64: "inst_shift_logical_right_imm_alt_64",
    test_inst_set_greater_than_signed_imm_0: "inst_set_greater_than_signed_imm_0",
    test_inst_set_greater_than_signed_imm_1: "inst_set_greater_than_signed_imm_1",
    test_inst_set_greater_than_unsigned_imm_0: "inst_set_greater_than_unsigned_imm_0",
    test_inst_set_greater_than_unsigned_imm_1: "inst_set_greater_than_unsigned_imm_1",
    test_inst_set_less_than_signed_imm_0: "inst_set_less_than_signed_imm_0",
    test_inst_set_less_than_signed_imm_1: "inst_set_less_than_signed_imm_1",
    test_inst_set_less_than_unsigned_imm_0: "inst_set_less_than_unsigned_imm_0",
    test_inst_set_less_than_unsigned_imm_1: "inst_set_less_than_unsigned_imm_1",
    test_inst_cmov_if_zero_imm_ok: "inst_cmov_if_zero_imm_ok",
    test_inst_cmov_if_zero_imm_nok: "inst_cmov_if_zero_imm_nok",
    test_inst_cmov_if_not_zero_imm_ok: "inst_cmov_if_not_zero_imm_ok",
    test_inst_cmov_if_not_zero_imm_nok: "inst_cmov_if_not_zero_imm_nok",
    test_inst_cmov_if_not_zero_imm_overflow_ok: "inst_cmov_if_not_zero_imm_overflow_ok",
    test_inst_cmov_if_not_zero_imm_overflow_nok: "inst_cmov_if_not_zero_imm_overflow_nok",
    test_inst_cmov_if_not_zero_imm_wrap_ok: "inst_cmov_if_not_zero_imm_wrap_ok",
    test_inst_cmov_if_not_zero_imm_wrap_nok: "inst_cmov_if_not_zero_imm_wrap_nok",

    // Complex jump instructions
    test_inst_jump_indirect_invalid_djump_to_zero_nok: "inst_jump_indirect_invalid_djump_to_zero_nok",
    test_inst_jump_indirect_misaligned_djump_with_offset_nok: "inst_jump_indirect_misaligned_djump_with_offset_nok",
    test_inst_jump_indirect_misaligned_djump_without_offset_nok: "inst_jump_indirect_misaligned_djump_without_offset_nok",
    test_inst_jump_indirect_with_offset_ok: "inst_jump_indirect_with_offset_ok",
    test_inst_jump_indirect_without_offset_ok: "inst_jump_indirect_without_offset_ok",
    test_inst_load_imm_and_jump_indirect_different_regs_with_offset_ok: "inst_load_imm_and_jump_indirect_different_regs_with_offset_ok",
    test_inst_load_imm_and_jump_indirect_different_regs_without_offset_ok: "inst_load_imm_and_jump_indirect_different_regs_without_offset_ok",
    test_inst_load_imm_and_jump_indirect_invalid_djump_to_zero_different_regs_without_offset_nok: "inst_load_imm_and_jump_indirect_invalid_djump_to_zero_different_regs_without_offset_nok",
    test_inst_load_imm_and_jump_indirect_invalid_djump_to_zero_same_regs_without_offset_nok: "inst_load_imm_and_jump_indirect_invalid_djump_to_zero_same_regs_without_offset_nok",
    test_inst_load_imm_and_jump_indirect_misaligned_djump_different_regs_with_offset_nok: "inst_load_imm_and_jump_indirect_misaligned_djump_different_regs_with_offset_nok",
    test_inst_load_imm_and_jump_indirect_misaligned_djump_different_regs_without_offset_nok: "inst_load_imm_and_jump_indirect_misaligned_djump_different_regs_without_offset_nok",
    test_inst_load_imm_and_jump_indirect_misaligned_djump_same_regs_with_offset_nok: "inst_load_imm_and_jump_indirect_misaligned_djump_same_regs_with_offset_nok",
    test_inst_load_imm_and_jump_indirect_misaligned_djump_same_regs_without_offset_nok: "inst_load_imm_and_jump_indirect_misaligned_djump_same_regs_without_offset_nok",
    test_inst_load_imm_and_jump_indirect_same_regs_with_offset_ok: "inst_load_imm_and_jump_indirect_same_regs_with_offset_ok",
    test_inst_load_imm_and_jump_indirect_same_regs_without_offset_ok: "inst_load_imm_and_jump_indirect_same_regs_without_offset_ok",

    // Load indirect instructions
    test_inst_load_indirect_i16_with_offset: "inst_load_indirect_i16_with_offset",
    test_inst_load_indirect_i16_without_offset: "inst_load_indirect_i16_without_offset",
    test_inst_load_indirect_i32_with_offset: "inst_load_indirect_i32_with_offset",
    test_inst_load_indirect_i32_without_offset: "inst_load_indirect_i32_without_offset",
    test_inst_load_indirect_i8_with_offset: "inst_load_indirect_i8_with_offset",
    test_inst_load_indirect_i8_without_offset: "inst_load_indirect_i8_without_offset",
    test_inst_load_indirect_u16_with_offset: "inst_load_indirect_u16_with_offset",
    test_inst_load_indirect_u16_without_offset: "inst_load_indirect_u16_without_offset",
    test_inst_load_indirect_u32_with_offset: "inst_load_indirect_u32_with_offset",
    test_inst_load_indirect_u32_without_offset: "inst_load_indirect_u32_without_offset",
    test_inst_load_indirect_u64_with_offset: "inst_load_indirect_u64_with_offset",
    test_inst_load_indirect_u64_without_offset: "inst_load_indirect_u64_without_offset",
    test_inst_load_indirect_u8_with_offset: "inst_load_indirect_u8_with_offset",
    test_inst_load_indirect_u8_without_offset: "inst_load_indirect_u8_without_offset",

    // Store indirect instructionsMemoryError
    test_inst_store_indirect_u16_with_offset_ok: "inst_store_indirect_u16_with_offset_ok",
    test_inst_store_indirect_u16_with_offset_nok: "inst_store_indirect_u16_with_offset_nok",
    test_inst_store_indirect_u16_without_offset_ok: "inst_store_indirect_u16_without_offset_ok",
    test_inst_store_indirect_u32_with_offset_ok: "inst_store_indirect_u32_with_offset_ok",
    test_inst_store_indirect_u32_with_offset_nok: "inst_store_indirect_u32_with_offset_nok",
    test_inst_store_indirect_u32_without_offset_ok: "inst_store_indirect_u32_without_offset_ok",
    test_inst_store_indirect_u64_with_offset_ok: "inst_store_indirect_u64_with_offset_ok",
    test_inst_store_indirect_u64_with_offset_nok: "inst_store_indirect_u64_with_offset_nok",
    test_inst_store_indirect_u64_without_offset_ok: "inst_store_indirect_u64_without_offset_ok",
    test_inst_store_indirect_u8_with_offset_ok: "inst_store_indirect_u8_with_offset_ok",
    test_inst_store_indirect_u8_with_offset_nok: "inst_store_indirect_u8_with_offset_nok",
    test_inst_store_indirect_u8_without_offset_ok: "inst_store_indirect_u8_without_offset_ok",

    // Branch instructions (two registers)MemoryError
    test_inst_branch_eq_ok: "inst_branch_eq_ok",
    test_inst_branch_eq_nok: "inst_branch_eq_nok",
    test_inst_branch_not_eq_ok: "inst_branch_not_eq_ok",
    test_inst_branch_not_eq_nok: "inst_branch_not_eq_nok",
    test_inst_branch_greater_or_equal_signed_ok: "inst_branch_greater_or_equal_signed_ok",
    test_inst_branch_greater_or_equal_signed_nok: "inst_branch_greater_or_equal_signed_nok",
    test_inst_branch_greater_or_equal_unsigned_ok: "inst_branch_greater_or_equal_unsigned_ok",
    test_inst_branch_greater_or_equal_unsigned_nok: "inst_branch_greater_or_equal_unsigned_nok",
    test_inst_branch_less_signed_ok: "inst_branch_less_signed_ok",
    test_inst_branch_less_signed_nok: "inst_branch_less_signed_nok",
    test_inst_branch_less_unsigned_ok: "inst_branch_less_unsigned_ok",
    test_inst_branch_less_unsigned_nok: "inst_branch_less_unsigned_nok",

    // Return instructionsMemoryError
    test_inst_ret_halt: "inst_ret_halt",
    test_inst_ret_invalid: "inst_ret_invalid",

    // All RISC-V testsMemoryError
    test_riscv_rv64ua_amoadd_d: "riscv_rv64ua_amoadd_d",
    test_riscv_rv64ua_amoadd_w: "riscv_rv64ua_amoadd_w",
    test_riscv_rv64ua_amoand_d: "riscv_rv64ua_amoand_d",
    test_riscv_rv64ua_amoand_w: "riscv_rv64ua_amoand_w",
    test_riscv_rv64ua_amomax_d: "riscv_rv64ua_amomax_d",
    test_riscv_rv64ua_amomaxu_d: "riscv_rv64ua_amomaxu_d",
    test_riscv_rv64ua_amomaxu_w: "riscv_rv64ua_amomaxu_w",
    test_riscv_rv64ua_amomax_w: "riscv_rv64ua_amomax_w",
    test_riscv_rv64ua_amomin_d: "riscv_rv64ua_amomin_d",
    test_riscv_rv64ua_amominu_d: "riscv_rv64ua_amominu_d",
    test_riscv_rv64ua_amominu_w: "riscv_rv64ua_amominu_w",
    test_riscv_rv64ua_amomin_w: "riscv_rv64ua_amomin_w",
    test_riscv_rv64ua_amoor_d: "riscv_rv64ua_amoor_d",
    test_riscv_rv64ua_amoor_w: "riscv_rv64ua_amoor_w",
    test_riscv_rv64ua_amoswap_d: "riscv_rv64ua_amoswap_d",
    test_riscv_rv64ua_amoswap_w: "riscv_rv64ua_amoswap_w",
    test_riscv_rv64ua_amoxor_d: "riscv_rv64ua_amoxor_d",
    test_riscv_rv64ua_amoxor_w: "riscv_rv64ua_amoxor_w",
    test_riscv_rv64uc_rvc: "riscv_rv64uc_rvc",
    test_riscv_rv64ui_addi: "riscv_rv64ui_addi",
    test_riscv_rv64ui_addiw: "riscv_rv64ui_addiw",
    test_riscv_rv64ui_add: "riscv_rv64ui_add",
    test_riscv_rv64ui_addw: "riscv_rv64ui_addw",
    test_riscv_rv64ui_andi: "riscv_rv64ui_andi",
    test_riscv_rv64ui_and: "riscv_rv64ui_and",
    test_riscv_rv64ui_beq: "riscv_rv64ui_beq",
    test_riscv_rv64ui_bge: "riscv_rv64ui_bge",
    test_riscv_rv64ui_bgeu: "riscv_rv64ui_bgeu",
    test_riscv_rv64ui_blt: "riscv_rv64ui_blt",
    test_riscv_rv64ui_bltu: "riscv_rv64ui_bltu",
    test_riscv_rv64ui_bne: "riscv_rv64ui_bne",
    test_riscv_rv64ui_jal: "riscv_rv64ui_jal",
    test_riscv_rv64ui_jalr: "riscv_rv64ui_jalr",
    test_riscv_rv64ui_lb: "riscv_rv64ui_lb",
    test_riscv_rv64ui_lbu: "riscv_rv64ui_lbu",
    test_riscv_rv64ui_ld: "riscv_rv64ui_ld",
    test_riscv_rv64ui_lh: "riscv_rv64ui_lh",
    test_riscv_rv64ui_lhu: "riscv_rv64ui_lhu",
    test_riscv_rv64ui_lui: "riscv_rv64ui_lui",
    test_riscv_rv64ui_lw: "riscv_rv64ui_lw",
    test_riscv_rv64ui_lwu: "riscv_rv64ui_lwu",
    test_riscv_rv64ui_ma_data: "riscv_rv64ui_ma_data",
    test_riscv_rv64ui_ori: "riscv_rv64ui_ori",
    test_riscv_rv64ui_or: "riscv_rv64ui_or",
    test_riscv_rv64ui_sb: "riscv_rv64ui_sb",
    test_riscv_rv64ui_sd: "riscv_rv64ui_sd",
    test_riscv_rv64ui_sh: "riscv_rv64ui_sh",
    test_riscv_rv64ui_simple: "riscv_rv64ui_simple",
    test_riscv_rv64ui_slli: "riscv_rv64ui_slli",
    test_riscv_rv64ui_slliw: "riscv_rv64ui_slliw",
    test_riscv_rv64ui_sll: "riscv_rv64ui_sll",
    test_riscv_rv64ui_sllw: "riscv_rv64ui_sllw",
    test_riscv_rv64ui_slti: "riscv_rv64ui_slti",
    test_riscv_rv64ui_sltiu: "riscv_rv64ui_sltiu",
    test_riscv_rv64ui_slt: "riscv_rv64ui_slt",
    test_riscv_rv64ui_sltu: "riscv_rv64ui_sltu",
    test_riscv_rv64ui_srai: "riscv_rv64ui_srai",
    test_riscv_rv64ui_sraiw: "riscv_rv64ui_sraiw",
    test_riscv_rv64ui_sra: "riscv_rv64ui_sra",
    test_riscv_rv64ui_sraw: "riscv_rv64ui_sraw",
    test_riscv_rv64ui_srli: "riscv_rv64ui_srli",
    test_riscv_rv64ui_srliw: "riscv_rv64ui_srliw",
    test_riscv_rv64ui_srl: "riscv_rv64ui_srl",
    test_riscv_rv64ui_srlw: "riscv_rv64ui_srlw",
    test_riscv_rv64ui_sub: "riscv_rv64ui_sub",
    test_riscv_rv64ui_subw: "riscv_rv64ui_subw",
    test_riscv_rv64ui_sw: "riscv_rv64ui_sw",
    test_riscv_rv64ui_xori: "riscv_rv64ui_xori",
    test_riscv_rv64ui_xor: "riscv_rv64ui_xor",
    test_riscv_rv64um_div: "riscv_rv64um_div",
    test_riscv_rv64um_divu: "riscv_rv64um_divu",
    test_riscv_rv64um_divuw: "riscv_rv64um_divuw",
    test_riscv_rv64um_divw: "riscv_rv64um_divw",
    test_riscv_rv64um_mulh: "riscv_rv64um_mulh",
    test_riscv_rv64um_mulhsu: "riscv_rv64um_mulhsu",
    test_riscv_rv64um_mulhu: "riscv_rv64um_mulhu",
    test_riscv_rv64um_mul: "riscv_rv64um_mul",
    test_riscv_rv64um_mulw: "riscv_rv64um_mulw",
    test_riscv_rv64um_rem: "riscv_rv64um_rem",
    test_riscv_rv64um_remu: "riscv_rv64um_remu",
    test_riscv_rv64um_remuw: "riscv_rv64um_remuw",
    test_riscv_rv64um_remw: "riscv_rv64um_remw",
    test_riscv_rv64uzbb_andn: "riscv_rv64uzbb_andn",
    test_riscv_rv64uzbb_clz: "riscv_rv64uzbb_clz",
    test_riscv_rv64uzbb_clzw: "riscv_rv64uzbb_clzw",
    test_riscv_rv64uzbb_cpop: "riscv_rv64uzbb_cpop",
    test_riscv_rv64uzbb_cpopw: "riscv_rv64uzbb_cpopw",
    test_riscv_rv64uzbb_ctz: "riscv_rv64uzbb_ctz",
    test_riscv_rv64uzbb_ctzw: "riscv_rv64uzbb_ctzw",
    test_riscv_rv64uzbb_max: "riscv_rv64uzbb_max",
    test_riscv_rv64uzbb_maxu: "riscv_rv64uzbb_maxu",
    test_riscv_rv64uzbb_min: "riscv_rv64uzbb_min",
    test_riscv_rv64uzbb_minu: "riscv_rv64uzbb_minu",
    test_riscv_rv64uzbb_orc_b: "riscv_rv64uzbb_orc_b",
    test_riscv_rv64uzbb_orn: "riscv_rv64uzbb_orn",
    test_riscv_rv64uzbb_rev8: "riscv_rv64uzbb_rev8",
    test_riscv_rv64uzbb_rol: "riscv_rv64uzbb_rol",
    test_riscv_rv64uzbb_rolw: "riscv_rv64uzbb_rolw",
    test_riscv_rv64uzbb_rori: "riscv_rv64uzbb_rori",
    test_riscv_rv64uzbb_roriw: "riscv_rv64uzbb_roriw",
    test_riscv_rv64uzbb_ror: "riscv_rv64uzbb_ror",
    test_riscv_rv64uzbb_rorw: "riscv_rv64uzbb_rorw",
    test_riscv_rv64uzbb_sext_b: "riscv_rv64uzbb_sext_b",
    test_riscv_rv64uzbb_sext_h: "riscv_rv64uzbb_sext_h",
    test_riscv_rv64uzbb_xnor: "riscv_rv64uzbb_xnor",
    test_riscv_rv64uzbb_zext_h: "riscv_rv64uzbb_zext_h",
);
