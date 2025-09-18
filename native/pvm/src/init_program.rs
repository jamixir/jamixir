use crate::core::consts::{LAYOUT_BUFFER_SIZE, MAX_ADDR, MIN_ADDR, PAGE_SIZE, ZP, ZZ};
use crate::core::Registers;
use crate::core::{Memory, Permission};

pub struct ProgramSegments<'a> {
    pub program_text: &'a [u8],
    pub data: &'a [u8],
    pub z: usize,
    pub s: usize,
    pub code: &'a [u8],
}

#[inline]
fn align_to_min_addr(x: usize) -> usize {
    x.div_ceil(ZZ) * ZZ
}
#[inline]
fn align_to_page_size(x: usize) -> usize {
    x.div_ceil(ZP) * ZP
}

pub fn parse_program_segments<'a>(program: &'a [u8]) -> Result<ProgramSegments<'a>, &'static str> {
    if program.len() < 15 {
        return Err("insufficient_bytes");
    }

    let o_size = u32::from_le_bytes([program[0], program[1], program[2], 0]) as usize;
    let w_size = u32::from_le_bytes([program[3], program[4], program[5], 0]) as usize;
    let z = u16::from_le_bytes([program[6], program[7]]) as usize;
    let s = u32::from_le_bytes([program[8], program[9], program[10], 0]) as usize;

    let mut offset = 11usize;

    // 4 bytes for c
    if program.len() < offset + o_size + w_size + 4 {
        return Err("invalid_program");
    }

    let o = &program[offset..offset + o_size];
    offset += o_size;
    let w = &program[offset..offset + w_size];
    offset += w_size;
    let c_size = u32::from_le_bytes([
        program[offset],
        program[offset + 1],
        program[offset + 2],
        program[offset + 3],
    ]) as usize;

    offset += 4;

    if program.len() < c_size + offset {
        return Err("invalid_program");
    }
    let c = &program[offset..offset + c_size];

    return Ok(ProgramSegments {
        program_text: o,
        data: w,
        z: z,
        s: s,
        code: c,
    });
}

pub fn initialize_program<'a>(
    program: &'a [u8],
    args: &'a [u8],
) -> Option<(&'a [u8], Registers, Memory)> {
    let program_segments = parse_program_segments(program).ok()?;
    let program_text_size = program_segments.program_text.len();
    let data_size = program_segments.data.len();
    let s = program_segments.s;
    let z = program_segments.z;

    if align_to_min_addr(program_text_size)
        + align_to_min_addr(data_size + z * PAGE_SIZE)
        + align_to_min_addr(s)
        > MAX_ADDR - 5 * MIN_ADDR - LAYOUT_BUFFER_SIZE
    {
        return None;
    }
    let registers = Registers::from_slice([
        0xFFFF_0000,       // register 0
        0xFEFE_0000,       // register 1
        0,                 // register 2
        0,                 // register 3
        0,                 // register 4
        0,                 // register 5
        0,                 // register 6
        0xFEFF_0000,       // register 7
        args.len() as u64, // register 8
        0,                 // register 9
        0,                 // register 10
        0,                 // register 11
        0,                 // register 12
    ]);
    let memory = construct_memory(&program_segments, args);
    Some((program_segments.code, registers, memory))
}

pub fn construct_memory<'a>(program_segments: &'a ProgramSegments<'a>, args: &'a [u8]) -> Memory {
    let mut builder = Memory::builder();
    let program_text = program_segments.program_text;
    let data = program_segments.data;
    let z = program_segments.z;
    let s = program_segments.s;

    // Compute boundaries
    let prog_start = MIN_ADDR;
    let prog_region_len = align_to_page_size(program_text.len());

    let data_start = 2 * MIN_ADDR + align_to_min_addr(program_text.len());
    let data_region_len = align_to_page_size(data.len()) + z * PAGE_SIZE;

    let heap_start = data_start + data_region_len;

    let stack_start = MAX_ADDR - 2 * MIN_ADDR - LAYOUT_BUFFER_SIZE - align_to_page_size(s);
    let stack_len = align_to_page_size(s);
    let heap_end = stack_start;

    let args_start = MAX_ADDR - MIN_ADDR - LAYOUT_BUFFER_SIZE;
    let args_region_len = align_to_page_size(args.len());

    // Program text
    builder
        .get_mut_slice(prog_start, program_text.len())
        .copy_from_slice(program_text);
    //  Data

    builder
        .get_mut_slice(data_start, data.len())
        .copy_from_slice(data);
    //  Args

    builder
        .get_mut_slice(args_start, args.len())
        .copy_from_slice(args);

    builder.set_access(prog_start, prog_region_len, Permission::Read);
    builder.set_access(data_start, data_region_len, Permission::ReadWrite);
    builder.set_access(stack_start, stack_len, Permission::ReadWrite);
    builder.set_access(args_start, args_region_len, Permission::Read);

    builder.set_heap_bounds(heap_start, heap_end);

    builder.build()
}
