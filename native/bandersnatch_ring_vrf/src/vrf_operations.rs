use ark_ec_vrfs::prelude::ark_serialize;
use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};
use ark_ec_vrfs::Secret;
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use bandersnatch::{Input, Output, Public, RingProof};
use rustler::{Error, NifResult, NifStruct};

use crate::ring_context::ring_context;
use crate::rustler_bridges::{FixedColumnsCommittedBridge, PublicBridge, SecretBridge};

type S = bandersnatch::BandersnatchSha512Ell2;
type RingCommitment = ark_ec_vrfs::ring::RingCommitment<S>;

#[derive(CanonicalSerialize, CanonicalDeserialize)]
struct RingVrfSignature {
    output: Output,
    proof: RingProof,
}

#[derive(NifStruct, Debug)]
#[module = "RingVRF.VerificationResult"]
pub struct VrfVerificationResult {
    pub verified: bool,
    pub vrf_output_hash: Vec<u8>,
}

fn vrf_input_point(vrf_input_data: &[u8]) -> Input {
    let point =
        <bandersnatch::BandersnatchSha512Ell2 as ark_ec_vrfs::Suite>::data_to_point(vrf_input_data)
            .unwrap();
    Input::from(point)
}

#[rustler::nif]
pub fn ring_vrf_verify(
    commitment: FixedColumnsCommittedBridge,
    vrf_input_data: Vec<u8>,
    aux_data: Vec<u8>,
    signature: Vec<u8>,
) -> NifResult<VrfVerificationResult> {
    use ark_ec_vrfs::ring::Verifier as _;
    let commitment: RingCommitment = commitment.into();

    let signature = RingVrfSignature::deserialize_compressed(&signature[..])
        .map_err(|_e| Error::Atom("invalid_signature"))?;

    let input = vrf_input_point(&vrf_input_data);

    let output = signature.output;

    let ring_ctx = ring_context()?;

    let verifier_key = ring_ctx.verifier_key_from_commitment(commitment);
    let verifier = ring_ctx.verifier(verifier_key);

    let verified = Public::verify(input, output, &aux_data, &signature.proof, &verifier).is_ok();

    let vrf_output_hash: Vec<u8> = output.hash()[..32]
        .try_into()
        .map_err(|_| Error::Atom("hash_conversion_failed"))?;

    Ok(VrfVerificationResult {
        verified,
        vrf_output_hash,
    })
}

#[rustler::nif]
fn ring_vrf_sign(
    ring: Vec<PublicBridge<S>>,
    secret: SecretBridge<S>,
    prover_idx: usize,
    vrf_input_data: Vec<u8>,
    aux_data: Vec<u8>,
) -> NifResult<Vec<u8>> {
    use ark_ec_vrfs::ring::Prover as _;

    let ring: Vec<Public> = ring.into_iter().map(|pk| pk.into()).collect();

    let input = vrf_input_point(&vrf_input_data);
    let secret: Secret<S> = secret.into();
    let output = secret.output(input);

    let pts: Vec<_> = ring.iter().map(|pk| pk.0).collect();

    let ring_ctx = ring_context()?;

    let prover_key = ring_ctx.prover_key(&pts);
    let prover = ring_ctx.prover(prover_key, prover_idx);
    let proof = secret.prove(input, output, aux_data, &prover);

    let signature = RingVrfSignature { output, proof };
    let mut buf = Vec::new();
    signature.serialize_compressed(&mut buf).unwrap();

    Ok(buf)
}
