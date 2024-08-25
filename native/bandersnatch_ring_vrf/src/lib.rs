use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};
use ark_ec_vrfs::{
    prelude::ark_serialize, suites::bandersnatch::edwards::RingContext, ScalarField,
};
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use bandersnatch::{IetfProof, Input, Output, PcsParams, Public, RingProof, Secret};
use rand_chacha::rand_core::SeedableRng;
use rustler::{Error, NifResult, NifStruct};
use std::sync::OnceLock;
use std::{fs::File, io::Read};

use ark_ec_vrfs::prelude::ark_ff::PrimeField;

static RING_CTX: OnceLock<RingContext> = OnceLock::new();
#[rustler::nif]
pub fn create_ring_context(file_path: String, ring_size: usize) -> NifResult<()> {
    RING_CTX.get_or_init(|| {
        let mut file = File::open(file_path).expect("Failed to open the SRS file");
        let mut buf = Vec::new();
        file.read_to_end(&mut buf)
            .expect("Failed to read the SRS file");

        let pcs_params = PcsParams::deserialize_uncompressed_unchecked(&mut &buf[..])
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

// This is the IETF `Prove` procedure output as described in section 2.2
// of the Bandersnatch VRFs specification
#[derive(CanonicalSerialize, CanonicalDeserialize)]
struct IetfVrfSignature {
    output: Output,
    proof: IetfProof,
}

type S = bandersnatch::BandersnatchSha512Ell2;
type PcsCommitment =
    ring_proof::pcs::kzg::commitment::KzgCommitment<<S as ark_ec_vrfs::ring::RingSuite>::Pairing>;

type RingCommitment = ark_ec_vrfs::ring::RingCommitment<S>;

#[derive(Clone, CanonicalSerialize, CanonicalDeserialize, PartialEq, Eq, Debug, NifStruct)]
#[module = "RingCommitment"]
pub struct FixedColumnsCommittedBridge {
    pub points: Vec<PcsCommitment>,
    pub ring_selector: PcsCommitment,
}

impl From<FixedColumnsCommittedBridge> for RingCommitment {
    fn from(bridge: FixedColumnsCommittedBridge) -> Self {
        Self {
            points: bridge.points.try_into().expect("sdfsdf"),
            ring_selector: bridge.ring_selector,
            phantom: Default::default(),
        }
    }
}

impl From<RingCommitment> for FixedColumnsCommittedBridge {
    fn from(commitment: RingCommitment) -> Self {
        Self {
            points: commitment.points.into(),
            ring_selector: commitment.ring_selector,
        }
    }
}

// This is the IETF `Prove` procedure output as described in section 4.2
// of the Bandersnatch VRFs specification
#[derive(CanonicalSerialize, CanonicalDeserialize)]
struct RingVrfSignature {
    output: Output,
    // This contains both the Pedersen proof and actual ring proof.
    proof: RingProof,
}

// Construct VRF Input Point from arbitrary data (section 1.2)
fn vrf_input_point(vrf_input_data: &[u8]) -> Input {
    let point =
        <bandersnatch::BandersnatchSha512Ell2 as ark_ec_vrfs::Suite>::data_to_point(vrf_input_data)
            .unwrap();
    Input::from(point)
}

#[rustler::nif]
pub fn create_commitment(ring: Vec<Public>) -> NifResult<FixedColumnsCommittedBridge> {
    let pts: Vec<_> = ring.iter().map(|pk| pk.0).collect();

    let verifier_key = ring_context()?.verifier_key(&pts);

    let commitment = verifier_key.commitment();

    Ok(commitment.into())
}

/// Anonymous VRF signature verification.
///
/// Used for tickets verification.
#[rustler::nif]
pub fn ring_vrf_verify(
    commitment: FixedColumnsCommittedBridge,
    vrf_input_data: Vec<u8>,
    aux_data: Vec<u8>,
    signature: Vec<u8>,
) -> NifResult<Vec<u8>> {
    use ark_ec_vrfs::ring::Verifier as _;
    let commitment: RingCommitment = commitment.into();

    let signature = RingVrfSignature::deserialize_compressed(&signature[..])
        .map_err(|_e| Error::Atom("invalid_signature"))?;

    let input = vrf_input_point(&vrf_input_data);

    let output = signature.output;

    let ring_ctx = ring_context()?;

    let verifier_key = ring_ctx.verifier_key_from_commitment(commitment);
    let verifier = ring_ctx.verifier(verifier_key);

    if Public::verify(input, output, &aux_data, &signature.proof, &verifier).is_err() {
        return Err(Error::Atom("verification_failed"));
    }

    let vrf_output_hash: Vec<u8> = output.hash()[..32]
        .try_into()
        .map_err(|_| Error::Atom("hash_conversion_failed"))?;

    Ok(vrf_output_hash)
}

#[rustler::nif]
fn ring_vrf_sign(
    ring: Vec<Public>,       // Vector of public keys as Vec<u8>
    secret: Secret,          // Secret key
    prover_idx: usize,       // Index of the prover
    vrf_input_data: Vec<u8>, // VRF input data
    aux_data: Vec<u8>,       // Auxiliary data
) -> NifResult<Vec<u8>> {
    use ark_ec_vrfs::ring::Prover as _;

    let input = vrf_input_point(&vrf_input_data);
    let output = secret.output(input);

    let pts: Vec<_> = ring.iter().map(|pk| pk.0).collect();

    let ring_ctx = ring_context()?;

    let prover_key = ring_ctx.prover_key(&pts);
    let prover = ring_ctx.prover(prover_key, prover_idx);
    let proof = secret.prove(input, output, aux_data, &prover);

    // Output and Ring Proof bundled together (as per section 2.2)
    let signature = RingVrfSignature { output, proof };
    let mut buf = Vec::new();
    signature.serialize_compressed(&mut buf).unwrap();

    Ok(buf)
}

#[rustler::nif]
fn generate_secret_from_seed(seed: Vec<u8>) -> NifResult<Secret> {
    let secret = Secret::from_seed(&seed); // Generate a new secret from the seed
    Ok(secret)
}

#[rustler::nif]
fn generate_secret_from_rand() -> NifResult<Secret> {
    let mut rng = rand_chacha::ChaCha20Rng::from_entropy();
    let secret = Secret::from_rand(&mut rng); // Generate a new secret using random number generator
    Ok(secret)
}

#[rustler::nif]
fn generate_secret_from_scalar(scalar_bytes: Vec<u8>) -> NifResult<Secret> {
    let scalar = ScalarField::<S>::from_le_bytes_mod_order(&scalar_bytes[..]);
    let secret = Secret::from_scalar(scalar);
    Ok(secret)
}

rustler::init!("Elixir.BandersnatchRingVrf");
