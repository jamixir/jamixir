use crate::core::{consts::TERMINATION_INSTRUCTIONS, BitMask, Program};

#[derive(Debug)]
pub struct StartSet {
    set: Vec<u64>,
}

impl StartSet {
    fn to_index(&self, index: usize) -> (usize, usize) {
        (index >> 6, index & 63)
    }

    fn new(size: usize) -> Self {
        Self {
            set: vec![0u64; size],
        }
    }

    pub fn build(program: &Program, bitmask: &BitMask) -> Self {
        let num_words = program.len().div_ceil(64);
        let mut start_set = Self::new(num_words);
        start_set.add(0);

        let mut pos = 0;
        while pos < program.len() {
            let opcode = program[pos];
            let next_pos = pos + 1 + bitmask.skip(pos);
            // Check if current position is a termination instruction
            // since we  are jumping using skip, we always land on an opcode
            // so there is no need to check if the position is set in the bitmask
            if TERMINATION_INSTRUCTIONS[opcode as usize] {
                // Mark the next instruction after termination as jumpable
                start_set.add(next_pos);
            }

            pos = next_pos;
        }

        start_set
    }

    #[inline(always)]
    pub fn includes(&self, index: usize) -> bool {
        let (word_index, bit_index) = self.to_index(index);

        if word_index >= self.set.len() {
            return false;
        }

        (self.set[word_index] & (1u64 << bit_index)) != 0
    }

    pub fn add(&mut self, index: usize) {
        self.set_bit(index);
    }

    fn assure_capacity(&mut self, index: usize) {
        if index >= self.set.len() {
            self.set.resize(index + 1, 0);
        }
    }

    fn set_bit(&mut self, index: usize) {
        let (word_index, bit_index) = self.to_index(index);

        self.assure_capacity(word_index);

        self.set[word_index] |= 1u64 << bit_index;
    }
}
