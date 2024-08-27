use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};
use ark_ec_vrfs::{prelude::ark_serialize, suites::bandersnatch::edwards::RingContext};
use ark_serialize::CanonicalDeserialize;
use rustler::{Error, NifResult};
use std::sync::OnceLock;
use std::{fs::File, io::Read};

static RING_CTX: OnceLock<RingContext> = OnceLock::new();

#[rustler::nif]
pub fn create_ring_context(file_path: String, ring_size: usize) -> NifResult<()> {
    RING_CTX.get_or_init(|| {
        let mut file = File::open(file_path).expect("Failed to open the SRS file");
        let mut buf = Vec::new();
        file.read_to_end(&mut buf)
            .expect("Failed to read the SRS file");

        let pcs_params = bandersnatch::PcsParams::deserialize_uncompressed_unchecked(&mut &buf[..])
            .expect("Failed to deserialize PCS parameters");
        RingContext::from_srs(ring_size, pcs_params).expect("Failed to create RingContext")
    });
    Ok(())
}

pub fn ring_context() -> Result<RingContext, rustler::Error> {
    RING_CTX
        .get()
        .ok_or(Error::Atom("ring_context_not_initialized"))
        .cloned()
}
