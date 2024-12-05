use ark_ec_vrfs::{
    prelude::ark_serialize,
    suites::bandersnatch::edwards::{self as bandersnatch, IetfProof},
    Secret,
};
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use bandersnatch::{Input, Output, Public, RingProof};
use rustler::{Atom, Binary, Env, Error, NifResult, OwnedBinary};

use crate::ring_context::ring_context;
use crate::rustler_bridges::{FixedColumnsCommittedBridge, PublicBridge, SecretBridge};

type S = bandersnatch::BandersnatchSha512Ell2;
type RingCommitment = ark_ec_vrfs::ring::RingCommitment<S>;
mod atoms {
    rustler::atoms! {
        ok,
        error,
        // Define specific error atoms
        invalid_signature,
        verification_failed,
        hash_conversion_failed,
        unknown_error
    }
}

#[derive(CanonicalSerialize, CanonicalDeserialize)]
struct RingVrfSignature {
    output: Output,
    proof: RingProof,
}

#[derive(CanonicalSerialize, CanonicalDeserialize)]
struct IetfVrfSignature {
    output: Output,
    proof: IetfProof,
}

fn vrf_input_point(vrf_input_data: &[u8]) -> Input {
    let point =
        <bandersnatch::BandersnatchSha512Ell2 as ark_ec_vrfs::Suite>::data_to_point(vrf_input_data)
            .unwrap();
    Input::from(point)
}

#[rustler::nif]
pub fn ring_vrf_verify<'a>(
    env: Env<'a>,
    commitment: FixedColumnsCommittedBridge,
    vrf_input_data: Binary,
    aux_data: Binary,
    signature: Binary,
) -> NifResult<(Atom, Binary<'a>)> {
    use ark_ec_vrfs::ring::Verifier as _;
    let commitment: RingCommitment = commitment.into();

    let signature = RingVrfSignature::deserialize_compressed(signature.as_slice())
        .map_err(|_e| Error::Term(Box::new(atoms::invalid_signature())))?;

    let input = vrf_input_point(&vrf_input_data);

    let output = signature.output;

    let ring_ctx = ring_context()?;

    let verifier_key = ring_ctx.verifier_key_from_commitment(commitment);
    let verifier = ring_ctx.verifier(verifier_key);

    Public::verify(
        input,
        output,
        aux_data.as_slice(),
        &signature.proof,
        &verifier,
    )
    .map_err(|_| Error::Term(Box::new(atoms::verification_failed())))?;

    let vrf_output_hash_vec: Vec<u8> = output.hash()[..32]
        .try_into()
        .map_err(|_| Error::Term(Box::new(atoms::hash_conversion_failed())))?;

    // Create an OwnedBinary from the Vec<u8>
    let mut vrf_output_hash_bin = OwnedBinary::new(vrf_output_hash_vec.len()).unwrap();
    vrf_output_hash_bin
        .as_mut_slice()
        .copy_from_slice(&vrf_output_hash_vec);

    Ok((atoms::ok(), vrf_output_hash_bin.release(env)))
}

#[rustler::nif]
fn ring_vrf_sign<'a>(
    env: Env<'a>,
    ring: Vec<PublicBridge<S>>,
    secret: SecretBridge<S>,
    prover_idx: usize,
    vrf_input_data: Binary,
    aux_data: Binary,
) -> NifResult<(Binary<'a>, Binary<'a>)> {
    use ark_ec_vrfs::ring::Prover as _;

    let ring: Vec<Public> = ring.into_iter().map(|pk| pk.into()).collect();

    let input = vrf_input_point(&vrf_input_data);
    let secret: Secret<S> = secret.into();
    let output = secret.output(input);

    let pts: Vec<_> = ring.iter().map(|pk| pk.0).collect();

    let ring_ctx = ring_context()?;

    let prover_key = ring_ctx.prover_key(&pts);
    let prover = ring_ctx.prover(prover_key, prover_idx);
    let proof = secret.prove(input, output, aux_data.as_slice(), &prover);

    let signature = RingVrfSignature { output, proof };
    let mut buf = Vec::new();
    signature.serialize_compressed(&mut buf).unwrap();

    let mut signature_binary = OwnedBinary::new(buf.len()).unwrap();
    signature_binary.as_mut_slice().copy_from_slice(&buf);

    let vrf_output_hash_vec: Vec<u8> = output.hash()[..32]
        .try_into()
        .map_err(|_| Error::Term(Box::new(atoms::hash_conversion_failed())))?;

    let mut vrf_output_hash_bin = OwnedBinary::new(vrf_output_hash_vec.len()).unwrap();
    vrf_output_hash_bin
        .as_mut_slice()
        .copy_from_slice(&vrf_output_hash_vec);

    Ok((
        signature_binary.release(env),
        vrf_output_hash_bin.release(env),
    ))
}

#[rustler::nif]
fn ietf_vrf_sign<'a>(
    env: Env<'a>,
    secret_bridge: SecretBridge<S>,
    vrf_input_data: Binary,
    aux_data: Binary,
) -> NifResult<(Binary<'a>, Binary<'a>)> {
    use ark_ec_vrfs::ietf::Prover as _;

    let input = vrf_input_point(&vrf_input_data);
    let secret: Secret<S> = secret_bridge.into();
    let output = secret.output(input);

    let proof = secret.prove(input, output, aux_data.as_slice());

    let signature = IetfVrfSignature { output, proof };
    let mut buf = Vec::new();
    signature.serialize_compressed(&mut buf).unwrap();

    let mut signature_binary = OwnedBinary::new(buf.len()).unwrap();
    signature_binary.as_mut_slice().copy_from_slice(&buf);

    let vrf_output_hash_vec: Vec<u8> = output.hash()[..32]
        .try_into()
        .map_err(|_| Error::Term(Box::new(atoms::hash_conversion_failed())))?;

    let mut vrf_output_hash_bin = OwnedBinary::new(vrf_output_hash_vec.len()).unwrap();
    vrf_output_hash_bin
        .as_mut_slice()
        .copy_from_slice(&vrf_output_hash_vec);

    Ok((
        signature_binary.release(env),
        vrf_output_hash_bin.release(env),
    ))
}

#[rustler::nif]
pub fn ietf_vrf_verify_key<'a>(
    env: Env<'a>,
    key: PublicBridge<S>,
    vrf_input_data: Binary,
    aux_data: Binary,
    signature: Binary,
) -> NifResult<(Atom, Binary<'a>)> {
    do_ietf_vrf_verify_key(env, key, vrf_input_data, aux_data, signature)
}

pub fn do_ietf_vrf_verify_key<'a>(
    env: Env<'a>,
    key: PublicBridge<S>,
    vrf_input_data: Binary,
    aux_data: Binary,
    signature: Binary,
) -> NifResult<(Atom, Binary<'a>)> {
    use ark_ec_vrfs::ietf::Verifier as _;

    let signature = IetfVrfSignature::deserialize_compressed(signature.as_slice())
        .map_err(|_e| Error::Term(Box::new(atoms::invalid_signature())))?;

    let input = vrf_input_point(&vrf_input_data);
    let output = signature.output;

    let public: Public = key.into();

    // Attempt to verify the signature
    public
        .verify(input, output, aux_data.as_slice(), &signature.proof)
        .map_err(|_| Error::Term(Box::new(atoms::verification_failed())))?;

    let vrf_output_hash_vec: Vec<u8> = match output.hash()[..32].try_into() {
        Ok(hash) => hash,
        Err(_) => return Err(Error::Term(Box::new(atoms::hash_conversion_failed()))),
    };

    let mut vrf_output_hash_bin = OwnedBinary::new(vrf_output_hash_vec.len()).unwrap();
    vrf_output_hash_bin
        .as_mut_slice()
        .copy_from_slice(&vrf_output_hash_vec);

    Ok((atoms::ok(), vrf_output_hash_bin.release(env)))
}

#[rustler::nif]
fn ietf_vrf_verify<'a>(
    env: Env<'a>,
    ring: Vec<PublicBridge<S>>,
    vrf_input_data: Binary,
    aux_data: Binary,
    signature: Binary,
    signer_key_index: usize,
) -> NifResult<(Atom, Binary<'a>)> {
    do_ietf_vrf_verify_key(
        env,
        ring[signer_key_index],
        vrf_input_data,
        aux_data,
        signature,
    )
}
