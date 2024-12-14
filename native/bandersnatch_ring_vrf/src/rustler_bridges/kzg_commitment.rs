use crate::rustler_bridges::types::PcsCommitment;
use ark_ec::pairing::Pairing;
use ark_ec_vrfs::{
    prelude::ark_serialize::{CanonicalDeserialize, CanonicalSerialize},
    ring::RingSuite,
};
use rustler::{Decoder, Encoder, Env, NifResult, Term};

#[derive(Clone, Debug, PartialEq, Eq, CanonicalSerialize, CanonicalDeserialize)]
pub struct KzgCommitmentBridge<S: RingSuite>(pub <<S as RingSuite>::Pairing as Pairing>::G1Affine);

impl<S: RingSuite> Encoder for KzgCommitmentBridge<S> {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let mut bytes = Vec::new();
        self.0.serialize_compressed(&mut bytes).unwrap();
        bytes.encode(env)
    }
}

impl<'a, S: RingSuite + 'a> Decoder<'a> for KzgCommitmentBridge<S> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bytes: Vec<u8> = term.decode()?;
        let affine =
            <<S as RingSuite>::Pairing as Pairing>::G1Affine::deserialize_compressed(&*bytes)
                .map_err(|_| rustler::Error::Atom("deserialization_failed"))?;
        Ok(KzgCommitmentBridge(affine))
    }
}

impl<S: RingSuite> From<PcsCommitment<S>> for KzgCommitmentBridge<S> {
    fn from(commitment: PcsCommitment<S>) -> Self {
        KzgCommitmentBridge(commitment.0)
    }
}

impl<S: RingSuite> From<KzgCommitmentBridge<S>> for PcsCommitment<S> {
    fn from(bridge: KzgCommitmentBridge<S>) -> Self {
        ring_proof::pcs::kzg::commitment::KzgCommitment(bridge.0)
    }
}
