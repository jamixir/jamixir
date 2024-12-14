use ark_ec::{pairing::Pairing, AffineRepr};
use ark_ec_vrfs::{
    prelude::{ark_ff::PrimeField, ark_serialize},
    ring::{RingCommitment, RingSuite},
    Suite,
};
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use rustler::{Decoder, Encoder, Env, NifResult, Term};

use crate::rustler_bridges::KzgCommitmentBridge;

#[derive(Clone, CanonicalSerialize, CanonicalDeserialize, PartialEq, Eq, Debug)]
pub struct FixedColumnsCommittedBridge<S: RingSuite> {
    pub points: Vec<KzgCommitmentBridge<S::Pairing>>,
    pub ring_selector: KzgCommitmentBridge<S::Pairing>,
}

impl<S: RingSuite> Encoder for FixedColumnsCommittedBridge<S> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
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
            let point = <<S::Pairing as Pairing>::G1Affine>::deserialize_compressed(&mut reader)
                .map_err(|_| rustler::Error::Atom("deserialization_failed"))?;
            points.push(KzgCommitmentBridge(point));
        }

        // Deserialize ring_selector
        let ring_selector =
            <<S::Pairing as Pairing>::G1Affine>::deserialize_compressed(&mut reader)
                .map_err(|_| rustler::Error::Atom("deserialization_failed"))?;

        Ok(FixedColumnsCommittedBridge {
            points,
            ring_selector: KzgCommitmentBridge(ring_selector),
        })
    }
}

impl<S: RingSuite> From<FixedColumnsCommittedBridge<S>> for RingCommitment<S>
where
    <<S as Suite>::Affine as AffineRepr>::BaseField: PrimeField,
{
    fn from(bridge: FixedColumnsCommittedBridge<S>) -> Self {
        Self {
            points: bridge
                .points
                .into_iter()
                .map(|point| point.into())
                .collect::<Vec<_>>()
                .try_into()
                .expect("Conversion failed"),
            ring_selector: bridge.ring_selector.into(),
            phantom: Default::default(),
        }
    }
}

impl<S: RingSuite> From<RingCommitment<S>> for FixedColumnsCommittedBridge<S>
where
    <<S as Suite>::Affine as AffineRepr>::BaseField: PrimeField,
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
