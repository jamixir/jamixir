use ark_ec_vrfs::{Codec, ScalarField, Secret, Suite};
use rustler::{Decoder, Encoder, NifResult, Term};

use super::PublicBridge;

#[derive(Debug, Clone, PartialEq)]
pub struct SecretBridge<S: Suite> {
    pub scalar: ScalarField<S>,
    pub public: PublicBridge<S>,
}

impl<S: Suite> Encoder for SecretBridge<S> {
    fn encode<'b>(&self, env: rustler::Env<'b>) -> Term<'b> {
        let mut scalar_buf: Vec<u8> = Vec::new();

        S::Codec::scalar_encode(&self.scalar, &mut scalar_buf);

        let mut scalar_bin = rustler::OwnedBinary::new(scalar_buf.len()).unwrap();
        scalar_bin.as_mut_slice().copy_from_slice(&scalar_buf);

        let public_term = self.public.encode(env);

        (scalar_bin.release(env), public_term).encode(env)
    }
}

impl<'a, S: Suite + 'a> Decoder<'a> for SecretBridge<S> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let (scalar_bin, public_term): (rustler::Binary, Term<'a>) = term.decode()?;

        let scalar = S::Codec::scalar_decode(scalar_bin.as_slice());

        let public = public_term.decode()?;

        Ok(SecretBridge { scalar, public })
    }
}

impl<S: Suite> From<Secret<S>> for SecretBridge<S> {
    fn from(secret: Secret<S>) -> Self {
        SecretBridge {
            scalar: secret.scalar,
            public: secret.public.into(),
        }
    }
}

impl<S: Suite> From<SecretBridge<S>> for Secret<S> {
    fn from(bridge: SecretBridge<S>) -> Self {
        Secret {
            scalar: bridge.scalar,
            public: bridge.public.into(), // Convert the PublicBridge back to the original Public
        }
    }
}
