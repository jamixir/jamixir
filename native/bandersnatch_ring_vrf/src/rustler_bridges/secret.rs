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

        // Encode the scalar field
        S::Codec::scalar_encode(&self.scalar, &mut scalar_buf);

        let mut scalar_bin = rustler::OwnedBinary::new(scalar_buf.len()).unwrap();
        scalar_bin.as_mut_slice().copy_from_slice(&scalar_buf);

        // Encode the public key as a Term
        let public_term = self.public.encode(env);

        // Combine both encoded parts into a tuple
        (scalar_bin.release(env), public_term).encode(env)
    }
}

impl<'a, S: Suite + 'a> Decoder<'a> for SecretBridge<S> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        // Decode the tuple containing the scalar and public parts
        let (scalar_bin, public_term): (rustler::Binary, Term<'a>) = term.decode()?;

        // Decode the scalar from the scalar buffer
        let scalar = S::Codec::scalar_decode(scalar_bin.as_slice());

        // Decode the public key using the existing Decoder implementation for Public<S>
        let public = public_term.decode()?;

        // Construct and return the Secret<S> instance
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
