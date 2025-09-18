use crate::core::{BitMask, Program};

pub struct Deblob {
    pub program: Program,
    pub bitmask: BitMask,
    pub jump_table: Vec<usize>,
}

pub fn deblob(bin: &[u8]) -> Deblob {
    let (jump_len, rest) = decode_next_integer(bin);
    let (z, rest) = decode_next_le(rest, 1);
    let (prog_len, rest) = decode_next_integer(rest);

    let (jump_table, rest) = decode_jump_table(rest, jump_len as usize, z);

    let (program_bytes, bitmask_bytes) = rest.split_at(prog_len as usize);
    let program = Program::new(program_bytes);

    let bitmask = BitMask::from_bytes(bitmask_bytes, prog_len as usize);

    Deblob {
        program,
        bitmask,
        jump_table,
    }
}

#[inline(always)]
fn decode_next_integer(bin: &[u8]) -> (u64, &[u8]) {
    if bin.is_empty() {
        return (0, bin);
    }

    match bin[0] {
        0 => (0, &bin[1..]),

        1..=127 => (bin[0] as u64, &bin[1..]),

        255 => {
            if bin.len() < 9 {
                panic!("decode_next_integer: not enough bytes for 8-byte integer");
            }
            let value = u64::from_le_bytes(bin[1..9].try_into().unwrap());
            (value, &bin[9..])
        }

        128..=254 => {
            let (l, a_l) = determine_l_and_a_l(bin[0]);
            if bin.len() < 1 + l {
                panic!("decode_next_integer: not enough bytes for medium integer");
            }
            let h = (bin[0] - a_l) as u64;
            let x_rest = decode_le(&bin[1..1 + l], l);
            let value = (h << (8 * l)) | x_rest;

            (value, &bin[1 + l..])
        }
    }
}

fn determine_l_and_a_l(byte0: u8) -> (usize, u8) {
    if byte0 >= 254 {
        (7, 254)
    } else if byte0 >= 252 {
        (6, 252)
    } else if byte0 >= 248 {
        (5, 248)
    } else if byte0 >= 240 {
        (4, 240)
    } else if byte0 >= 224 {
        (3, 224)
    } else if byte0 >= 192 {
        (2, 192)
    } else if byte0 >= 128 {
        (1, 128)
    } else {
        panic!("Invalid byte for determine_l_and_a_l: {}", byte0);
    }
}

#[inline(always)]
pub fn decode_le(bin: &[u8], l: usize) -> u64 {
    let mut buf = [0u8; 8];
    buf[..l].copy_from_slice(&bin[..l]);
    u64::from_le_bytes(buf)
}

#[inline(always)]
fn decode_next_le(bin: &[u8], l: usize) -> (u64, &[u8]) {
    let mut buf = [0u8; 8];
    buf[..l].copy_from_slice(&bin[0..l]);
    let value = u64::from_le_bytes(buf);
    (value, &bin[l..])
}

fn decode_jump_table(mut bin: &[u8], size: usize, z: u64) -> (Vec<usize>, &[u8]) {
    if size == 0 {
        return (Vec::new(), bin);
    }

    let mut values: Vec<usize> = Vec::with_capacity(size);
    let z_size = z as usize;

    for _ in 0..size {
        let (value, rest) = decode_next_le(bin, z_size);
        values.push(value as usize);
        bin = rest;
    }

    (values, bin)
}
