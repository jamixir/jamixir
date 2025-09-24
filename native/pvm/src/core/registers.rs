use rustler::{Decoder, Encoder, Env, Term};

#[derive(Debug, Clone, Copy)]
pub struct Registers {
    pub data: [u64; 13],
}

impl Registers {
    pub fn new() -> Self {
        Self { data: [0; 13] }
    }
    pub fn get(&self, index: usize) -> u64 {
        self.data[index]
    }
    pub fn set(&mut self, index: usize, value: u64) {
        self.data[index] = value;
    }

    pub fn from_slice(slice: [u64; 13]) -> Self {
        Self { data: slice }
    }

    pub fn from_vec(vec: Vec<u64>) -> Self {
        let mut data = [0u64; 13];
        let len = vec.len().min(13);
        data[..len].copy_from_slice(&vec[..len]);
        Self { data }
    }
}

impl Decoder<'_> for Registers {
    fn decode(term: Term) -> rustler::NifResult<Self> {
        let list: Vec<u64> = term.decode()?;
        let mut data = [0u64; 13];
        for (i, &value) in list.iter().take(13).enumerate() {
            data[i] = value;
        }
        Ok(Registers { data })
    }
}

impl Encoder for Registers {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        self.data.to_vec().encode(env)
    }
}
