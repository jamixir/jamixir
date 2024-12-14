use rustler::NifResult;
use crate::ring_context::ring_context;
use crate::rustler_bridges::{public::OptionalPublicBridge, types::{Bandersnatch, VerifierKey}, FixedColumnsCommittedBridge};


#[rustler::nif]
pub fn create_commitment_bandersnatch(
    ring: Vec<OptionalPublicBridge<Bandersnatch>>,
) -> NifResult<FixedColumnsCommittedBridge<Bandersnatch>> {
    let pts: Vec<_> = ring
        .into_iter()
        .filter_map(|OptionalPublicBridge(maybe_pk)| maybe_pk.map(|pk| pk.0))
        .collect();

    let ring_ctx: ark_ec_vrfs::ring::RingContext<Bandersnatch> = ring_context()?;

    let verifier_key: VerifierKey<Bandersnatch> = ring_ctx.verifier_key(&pts);

    let commitment = verifier_key.commitment();

    Ok(commitment.into())
}
