use crate::rustler_bridges::{public::PublicBridge, FixedColumnsCommittedBridge};
use crate::{ring_context::ring_context, types::Bandersnatch as S};
use rustler::NifResult;

#[rustler::nif]
pub fn create_commitment(
    ring: Vec<PublicBridge<S>>,
) -> NifResult<FixedColumnsCommittedBridge> {
    let pts: Vec<_> = ring
        .into_iter()
        .map(|pk| pk.0)
        .collect();

    let commitment = ring_context()?.verifier_key(&pts).commitment();

    Ok(commitment.into())
}
