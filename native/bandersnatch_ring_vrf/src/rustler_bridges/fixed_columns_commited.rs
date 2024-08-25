use ark_ec_vrfs::prelude::ark_serialize;
use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use rustler::NifStruct;

use crate::rustler_bridges::KzgCommitmentBridge;

type S = bandersnatch::BandersnatchSha512Ell2;
type Pairing = <S as ark_ec_vrfs::ring::RingSuite>::Pairing;
type KzgCommitmentVec = Vec<KzgCommitmentBridge<Pairing>>;
type RingCommitment = ark_ec_vrfs::ring::RingCommitment<S>;

#[derive(Clone, CanonicalSerialize, CanonicalDeserialize, PartialEq, Eq, Debug, NifStruct)]
#[module = "RingCommitment"]
pub struct FixedColumnsCommittedBridge {
    pub points: KzgCommitmentVec,
    pub ring_selector: KzgCommitmentBridge<Pairing>,
}

impl From<FixedColumnsCommittedBridge> for RingCommitment {
    fn from(bridge: FixedColumnsCommittedBridge) -> Self {
        Self {
            points: bridge
                .points
                .into_iter()
                .map(|point| point.into()) // Convert each `KzgCommitmentBridge` into `KzgCommitment`
                .collect::<Vec<_>>()
                .try_into()
                .expect("Conversion failed"),
            ring_selector: bridge.ring_selector.into(), // Convert `KzgCommitmentBridge` into `KzgCommitment`
            phantom: Default::default(),
        }
    }
}

impl From<RingCommitment> for FixedColumnsCommittedBridge {
    fn from(commitment: RingCommitment) -> Self {
        Self {
            points: commitment
                .points
                .into_iter()
                .map(|point| point.into()) // Convert each `KzgCommitment` into `KzgCommitmentBridge`
                .collect(),
            ring_selector: commitment.ring_selector.into(), // Convert `KzgCommitment` into `KzgCommitmentBridge`
        }
    }
}