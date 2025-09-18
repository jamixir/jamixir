use std::ops::Index;

#[derive(Debug)]
pub struct BitMask {
    pub bits: Vec<u64>,
    limit: usize,
}

impl BitMask {
    fn to_index(&self, index: usize) -> (usize, usize) {
        (index >> 6, index & 63)
    }

    pub fn from_bytes(bytes: &[u8], program_length: usize) -> Self {
        let mut words: Vec<u64> = bytes
            .chunks_exact(8)
            .map(|chunk| u64::from_le_bytes(chunk.try_into().unwrap()))
            .collect();

        let remainder = bytes.chunks_exact(8).remainder();
        if !remainder.is_empty() {
            let mut buf = [0u8; 8];
            buf[..remainder.len()].copy_from_slice(&remainder);
            words.push(u64::from_le_bytes(buf));
        }

        let mut bitmask = Self {
            bits: words,
            limit: program_length,
        };
        bitmask.pad();
        bitmask
    }

    fn assure_capacity(&mut self, index: usize) {
        if index >= self.bits.len() {
            self.bits.resize(index + 1, 0);
        }
    }
    pub fn size(&self) -> usize {
        (self.limit + 63) >> 6
    }

    pub fn program_limit(&self) -> usize {
        self.limit
    }

    #[inline(always)]
    pub fn is_set(&self, index: usize) -> bool {
        let (word_index, bit_index) = self.to_index(index);

        if word_index >= self.bits.len() {
            return false;
        }

        (self.bits[word_index] & (1u64 << bit_index)) != 0
    }
    #[inline(always)]
    pub fn set_bit(&mut self, index: usize) {
        let (word_index, bit_index) = self.to_index(index);
        self.assure_capacity(word_index);

        self.bits[word_index] |= 1u64 << bit_index;
    }
    #[inline(always)]
    pub fn skip(&self, pc: usize) -> usize {
        let word_index = (pc + 1) >> 6;
        let bit_index = (pc + 1) & 63;
        let limit = self.bits.len();

        let curr = unsafe {
            if word_index < limit {
                *self.bits.as_ptr().add(word_index)
            } else {
                0
            }
        };
        let masked = curr >> bit_index;

        if masked != 0 {
            return (masked.trailing_zeros() as usize).min(24);
        }
        let next = unsafe {
            if word_index + 1 < limit {
                *self.bits.as_ptr().add(word_index + 1)
            } else {
                0
            }
        };

        let remain_curr = 64 - bit_index;
        (remain_curr + next.trailing_zeros() as usize).min(24)
    }

    #[inline]
    pub fn pad(&mut self) {
        let (word_index, bit_index) = self.to_index(self.limit);
        self.assure_capacity(word_index);

        let upper_mask = u64::MAX << bit_index;
        self.bits[word_index] |= upper_mask;

        self.bits.push(u64::MAX);
    }
}

impl Index<usize> for BitMask {
    type Output = u64;

    #[inline(always)]
    fn index(&self, index: usize) -> &Self::Output {
        unsafe { self.bits.get_unchecked(index) }
    }
}

impl Index<std::ops::Range<usize>> for BitMask {
    type Output = [u64];

    #[inline(always)]
    fn index(&self, range: std::ops::Range<usize>) -> &Self::Output {
        unsafe { self.bits.get_unchecked(range) }
    }
}
