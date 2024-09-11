use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};
use rustler::NifResult;

use crate::ring_context::ring_context;
use crate::rustler_bridges::public::OptionalPublicBridge;
use crate::rustler_bridges::FixedColumnsCommittedBridge;

type S = bandersnatch::BandersnatchSha512Ell2;

#[rustler::nif]
pub fn create_commitment(
    ring: Vec<OptionalPublicBridge<S>>,
) -> NifResult<FixedColumnsCommittedBridge> {
    let pts: Vec<_> = ring
        .into_iter()
        .filter_map(|OptionalPublicBridge(maybe_pk)| maybe_pk.map(|pk| pk.0))
        .collect();

    let verifier_key = ring_context()?.verifier_key(&pts);

    let commitment = verifier_key.commitment();

    Ok(commitment.into())
}
