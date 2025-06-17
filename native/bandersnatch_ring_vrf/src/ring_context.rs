use ark_serialize::CanonicalDeserialize;
use ark_vrf::{
    reexports::ark_serialize,
    suites::bandersnatch::{PcsParams, RingProofParams},
};
use rustler::{Error, NifResult};
use std::sync::OnceLock;

static RING_CTX: OnceLock<RingProofParams> = OnceLock::new();
static SRS_FILE: &[u8] = include_bytes!("./zcash-srs-2-11-compressed.bin");

#[rustler::nif]
pub fn create_ring_context(ring_size: usize) -> NifResult<()> {
    RING_CTX.get_or_init(|| {
        let pcs_params = PcsParams::deserialize_compressed(&mut &SRS_FILE[..])
            .expect("Failed to deserialize PCS parameters");
        RingProofParams::from_pcs_params(ring_size, pcs_params)
            .expect("Failed to create RingContext")
    });
    Ok(())
}

pub fn ring_context() -> Result<RingProofParams, rustler::Error> {
    RING_CTX
        .get()
        .ok_or(Error::Atom("ring_context_not_initialized"))
        .cloned()
}
