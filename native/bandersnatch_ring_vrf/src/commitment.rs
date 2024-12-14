use crate::rustler_bridges::{public::OptionalPublicBridge, FixedColumnsCommittedBridge};
use crate::{ring_context::ring_context, types::Bandersnatch};
use rustler::NifResult;

#[rustler::nif]
pub fn create_commitment(
    ring: Vec<OptionalPublicBridge<Bandersnatch>>,
) -> NifResult<FixedColumnsCommittedBridge<Bandersnatch>> {
    let pts: Vec<_> = ring
        .into_iter()
        .filter_map(|OptionalPublicBridge(maybe_pk)| maybe_pk.map(|pk| pk.0))
        .collect();

    let commitment = ring_context()?.verifier_key(&pts).commitment();

    Ok(commitment.into())
}
