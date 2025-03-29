use ark_ec_vrfs::reexports::{
    ark_ec::pairing::Pairing,
    ark_serialize::{CanonicalDeserialize, CanonicalSerialize},
};
use ring_proof::pcs::kzg::commitment::KzgCommitment;
use rustler::{Decoder, Encoder, Env, NifResult, Term};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KzgCommitmentBridge<E: Pairing>(pub E::G1Affine);

impl<E: Pairing> Encoder for KzgCommitmentBridge<E> {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let mut bytes = Vec::new();
        self.0.serialize_compressed(&mut bytes).unwrap();
        bytes.encode(env)
    }
}

impl<'a, E: Pairing> Decoder<'a> for KzgCommitmentBridge<E> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bytes: Vec<u8> = term.decode()?;
        let affine = E::G1Affine::deserialize_compressed(&*bytes)
            .map_err(|_| rustler::Error::Atom("deserialization_failed"))?;
        Ok(KzgCommitmentBridge(affine))
    }
}

impl<E: Pairing> From<KzgCommitment<E>> for KzgCommitmentBridge<E> {
    fn from(commitment: KzgCommitment<E>) -> Self {
        KzgCommitmentBridge(commitment.0)
    }
}

impl<E: Pairing> From<KzgCommitmentBridge<E>> for KzgCommitment<E> {
    fn from(bridge: KzgCommitmentBridge<E>) -> Self {
        KzgCommitment(bridge.0)
    }
}
