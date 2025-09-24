pub fn encode_program(
    program: &[u8],
    bitmask_bytes: &[u8],
    jump_table: &[usize],
    z: u64,
) -> Vec<u8> {
    // Preallocate output buffer roughly
    let mut encoded = Vec::with_capacity(
        16 + program.len() + bitmask_bytes.len() + jump_table.len() * z as usize,
    );

    encode_integer(jump_table.len() as u64, &mut encoded);

    encoded.push(z as u8);

    encode_integer(program.len() as u64, &mut encoded);

    for &entry in jump_table {
        let le_bytes = encode_le(entry as u64, z as usize);
        encoded.extend_from_slice(&le_bytes[..z as usize]);
    }

    encoded.extend_from_slice(program);

    encoded.extend_from_slice(bitmask_bytes);

    encoded
}

#[inline]
fn encode_le(n: u64, l: usize) -> [u8; 8] {
    let bytes = n.to_le_bytes();
    let mut buf = [0u8; 8];
    buf[..l].copy_from_slice(&bytes[..l]);
    buf
}

fn exists_l_in_n8(x: u64) -> Option<usize> {
    if x == 0 {
        return Some(0);
    }
    // floor(log2(x)/7)
    let l = (63 - x.leading_zeros()) / 7;
    if l <= 7 {
        Some(l as usize)
    } else {
        None
    }
}

fn encode_integer(x: u64, out: &mut Vec<u8>) {
    if x == 0 {
        out.push(0);
        return;
    }

    if let Some(l) = exists_l_in_n8(x) {
        // l = trunc(log2(x)/7)
        // Marker byte = 256 - 2^(8-l) + top part of x
        let marker = 256u64 - (1u64 << (8 - l)) + (x >> (8 * l));
        out.push(marker as u8);

        // Remaining l bytes
        let rem = x & ((1u64 << (8 * l)) - 1);
        let le_bytes = encode_le(rem, l);
        out.extend_from_slice(&le_bytes[..l]);
    } else {
        // x too big, 8-byte literal
        out.push(255);
        out.extend_from_slice(&x.to_le_bytes());
    }
}
