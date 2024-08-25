use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};
use ark_ec_vrfs::prelude::ark_serialize;
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use bandersnatch::Public;
use rustler::{ NifResult, NifStruct};

use crate::ring_context::ring_context;

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
            points: bridge.points.try_into().expect("Conversion failed"),
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

#[rustler::nif]
pub fn create_commitment(ring: Vec<Public>) -> NifResult<FixedColumnsCommittedBridge> {
    let pts: Vec<_> = ring.iter().map(|pk| pk.0).collect();

    let verifier_key = ring_context()?.verifier_key(&pts);

    let commitment = verifier_key.commitment();

    Ok(commitment.into())
}
