use ark_ec::pairing::Pairing as PairingTrait;
use ark_ec::AffineRepr;
use ark_ec_vrfs::prelude::ark_ff::PrimeField;
use ark_ec_vrfs::prelude::ark_serialize;
use ark_ec_vrfs::ring::RingSuite;
use ark_ec_vrfs::ring::RingCommitment;
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use rustler::{Decoder, Encoder, Env, NifResult, Term};

use crate::rustler_bridges::KzgCommitmentBridge;
pub type Pairing<S> = <S as RingSuite>::Pairing;
// pub type RingCommitment<S> =
//     ring_proof::FixedColumnsCommitted<ark_ec_vrfs::BaseField<S>, PcsCommitment<S>>;

// type S = bandersnatch::BandersnatchSha512Ell2;

// type RingCommitment = ark_ec_vrfs::ring::RingCommitment<S>;

#[derive(Clone, CanonicalSerialize, CanonicalDeserialize, PartialEq, Eq, Debug)]
pub struct FixedColumnsCommittedBridge<S: RingSuite> {
    pub points: Vec<KzgCommitmentBridge<S>>,
    pub ring_selector: KzgCommitmentBridge<S>,
}

impl<S: RingSuite> Encoder for FixedColumnsCommittedBridge<S> {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let mut points_buf = Vec::new();
        for point in &self.points {
            point.0.serialize_compressed(&mut points_buf).unwrap();
        }

        let mut ring_selector_buf = Vec::new();
        self.ring_selector
            .0
            .serialize_compressed(&mut ring_selector_buf)
            .unwrap();

        // Combine all buffers into a single binary
        let mut combined_buf = points_buf;
        combined_buf.extend_from_slice(&ring_selector_buf);

        let mut binary = rustler::OwnedBinary::new(combined_buf.len()).unwrap();
        binary.as_mut_slice().copy_from_slice(&combined_buf);

        binary.release(env).encode(env)
    }
}

impl<'a, S: RingSuite + 'a> Decoder<'a> for FixedColumnsCommittedBridge<S> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let binary: rustler::Binary = term.decode()?;
        let mut reader = std::io::Cursor::new(binary.as_slice());

        // Deserialize points
        let mut points = Vec::new();
        for _ in 0..2 {
            let point =
                <<Pairing<S> as PairingTrait>::G1Affine>::deserialize_compressed(&mut reader)
                    .map_err(|_| rustler::Error::Atom("deserialization_failed"))?;
            points.push(KzgCommitmentBridge(point));
        }

        // Deserialize ring_selector
        let ring_selector =
            <<Pairing<S> as PairingTrait>::G1Affine>::deserialize_compressed(&mut reader)
                .map_err(|_| rustler::Error::Atom("deserialization_failed"))?;

        Ok(FixedColumnsCommittedBridge {
            points,
            ring_selector: KzgCommitmentBridge(ring_selector),
        })
    }
}

impl<S: RingSuite> From<FixedColumnsCommittedBridge<S>> for RingCommitment<S>
where
    <<S as RingSuite>::Pairing as PairingTrait>::G1Affine: AffineRepr,
    ark_ec_vrfs::BaseField<S>: PrimeField,
{
    fn from(bridge: FixedColumnsCommittedBridge<S>) -> Self {
        ring_proof::FixedColumnsCommitted {
            points: [
                ring_proof::pcs::kzg::commitment::KzgCommitment(bridge.points[0].0),
                ring_proof::pcs::kzg::commitment::KzgCommitment(bridge.points[1].0),
            ],
            ring_selector: ring_proof::pcs::kzg::commitment::KzgCommitment(bridge.ring_selector.0),
            phantom: Default::default(),
        }
    }
}

impl<S: RingSuite> From<RingCommitment<S>> for FixedColumnsCommittedBridge<S>
where
    <<S as RingSuite>::Pairing as PairingTrait>::G1Affine: AffineRepr,
    ark_ec_vrfs::BaseField<S>: PrimeField,
{
    fn from(commitment: RingCommitment<S>) -> Self {
        Self {
            points: commitment
                .points
                .into_iter()
                .map(|point| point.into())
                .collect(),
            ring_selector: commitment.ring_selector.into(),
        }
    }
}
