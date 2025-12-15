//! Reed-Solomon Erasure Coding for JAM
//!
//! # Data Layout
//!
//! The JAM test vectors uses **column-major** input: data is divided into C contiguous regions.
//! each region is a shard.
//!
//! ```text
//! Input:  [─── Col 0 ───][─── Col 1 ───] ... [─── Col C-1 ───]
//!
//! As a matrix (we iterate row-by-row for encoding/decoding):
//!
//!                   Col 0     Col 1    ...   Col C-1
//! Row 0:           [Symbol]  [Symbol]  ...  [Symbol]
//! Row 1:           [Symbol]  [Symbol]  ...  [Symbol]
//!   ...
//! Row N-1:         [Symbol]  [Symbol]  ...  [Symbol]
//! ```

use reed_solomon_simd::{ReedSolomonDecoder, ReedSolomonEncoder};
use std::error::Error;

const SYMBOL_SIZE: usize = 2;

type Symbol = [u8; 2];
type Shard = Vec<u8>;

fn to_symbol(slice: &[u8]) -> Symbol {
    [slice[0], slice[1]]
}

struct Config {
    num_cols: usize,       // C = core count
    num_rows: usize,       // N = symbols per column
    recovery_count: usize, // V - C
    col_bytes: usize,      // bytes per column (shard)
}

impl Config {
    fn new(data_len: usize, num_cols: usize) -> Self {
        let col_bytes = round_up(data_len.div_ceil(num_cols), SYMBOL_SIZE);
        let num_rows = col_bytes / SYMBOL_SIZE;
        let total_shards = if num_cols == 2 { 6 } else { 1023 };

        Self {
            num_cols,
            num_rows,
            recovery_count: total_shards - num_cols,
            col_bytes,
        }
    }

    fn padded_len(&self) -> usize {
        self.num_rows * self.num_cols * SYMBOL_SIZE
    }

    /// Get symbol at (row, col) from column-major data
    fn symbol_offset(&self, row: usize, col: usize) -> usize {
        col * self.col_bytes + row * SYMBOL_SIZE
    }
}

fn round_up(value: usize, multiple: usize) -> usize {
    let r = value % multiple;
    if r == 0 {
        value
    } else {
        value + (multiple - r)
    }
}

pub fn do_encode(data: Vec<u8>, core_count: usize) -> Result<Vec<Shard>, Box<dyn Error>> {
    let config = Config::new(data.len(), core_count);

    // Pad to align with symbol boundaries
    let mut padded = data;
    padded.resize(config.padded_len(), 0);

    // pre-allocate place for all the columns
    let mut original_shards: Vec<Shard> =
        vec![Vec::with_capacity(config.col_bytes); config.num_cols];
    let mut recovery_shards: Vec<Shard> =
        vec![Vec::with_capacity(config.col_bytes); config.recovery_count];

    // encode row by row
    for row in 0..config.num_rows {
        let mut encoder =
            ReedSolomonEncoder::new(config.num_cols, config.recovery_count, SYMBOL_SIZE)?;

        // Each symbol in the row goes to its column
        for col in 0..config.num_cols {
            let offset = config.symbol_offset(row, col);
            let symbol = &padded[offset..offset + SYMBOL_SIZE];
            encoder.add_original_shard(symbol)?;
            original_shards[col].extend_from_slice(symbol);
        }

        // Collect recovery symbols
        let encoded = encoder.encode()?;
        for (col, symbol) in encoded.recovery_iter().enumerate() {
            recovery_shards[col].extend_from_slice(symbol);
        }
    }

    Ok(original_shards.into_iter().chain(recovery_shards).collect())
}

pub fn do_decode(
    shards: Vec<Shard>,
    shard_indices: Vec<usize>,
    original_len: usize,
    core_count: usize,
) -> Result<Vec<u8>, Box<dyn Error>> {
    let config = Config::new(original_len, core_count);

    // Track which original columns we have
    // this is used in decode_row to in order to tell if a symbol in the Nth column
    // is coming from the input data or from recovered data
    let mut have_col: Vec<Option<usize>> = vec![None; core_count];
    for (pos, &idx) in shard_indices.iter().enumerate() {
        if idx < core_count {
            have_col[idx] = Some(pos);
        }
    }

    //  pre-allocate place for all the columns
    let mut original_shards: Vec<Shard> =
        vec![Vec::with_capacity(config.col_bytes); config.num_cols];

    // decode row by row
    for row in 0..config.num_rows {
        let row_symbols = decode_row(row, &shards, &shard_indices, &have_col, &config)?;

        for (col, symbol) in row_symbols.into_iter().enumerate() {
            original_shards[col].extend_from_slice(&symbol);
        }
    }

    // unroll matrix into a vector (column major) [col0 ++ col1 ++ ... ++ colC-1]
    let original_data: Vec<u8> = original_shards
        .into_iter()
        .flatten()
        .take(original_len)
        .collect();

    Ok(original_data)
}

fn decode_row(
    row: usize,
    shards: &[Shard],
    shard_indices: &[usize],
    have_col: &[Option<usize>],
    config: &Config,
) -> Result<Vec<Symbol>, Box<dyn Error>> {
    // create a decoder  per row, matching the  encoder
    let mut decoder = ReedSolomonDecoder::new(config.num_cols, config.recovery_count, SYMBOL_SIZE)?;

    let offset = row * SYMBOL_SIZE;
    for (pos, &shard_idx) in shard_indices.iter().enumerate() {
        let symbol = &shards[pos][offset..offset + SYMBOL_SIZE];

        if shard_idx < config.num_cols {
            decoder.add_original_shard(shard_idx, symbol)?;
        } else {
            decoder.add_recovery_shard(shard_idx - config.num_cols, symbol)?;
        }
    }

    let result = decoder.decode()?;

    let mut symbols = Vec::with_capacity(config.num_cols);
    for col in 0..config.num_cols {
        let symbol = match have_col[col] {
            // if the column is in the input data, use the original shard
            Some(pos) => to_symbol(&shards[pos][offset..offset + SYMBOL_SIZE]),
            // if the column is not in the input data, use the recovered shard
            None => to_symbol(
                result
                    .restored_original(col)
                    .ok_or("Reconstruction failed")?,
            ),
        };
        symbols.push(symbol); // full Symbol row of core_count columns
    }

    Ok(symbols)
}
