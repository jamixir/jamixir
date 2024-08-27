use ark_ec_vrfs::{AffinePoint, Codec, Public, Suite};
use rustler::{Decoder, Encoder, Env, NifResult, Term};

#[derive(Debug, Copy, Clone, PartialEq)]
pub struct PublicBridge<S: Suite>(pub AffinePoint<S>);

impl<S: Suite> Encoder for PublicBridge<S> {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut buf = Vec::new();
        S::Codec::point_encode(&self.0, &mut buf);

        let mut point_bin = rustler::OwnedBinary::new(buf.len()).unwrap();
        point_bin.as_mut_slice().copy_from_slice(&buf);

        point_bin.release(env).encode(env)
    }
}

impl<'a, S: Suite + 'a> Decoder<'a> for PublicBridge<S> {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let binary: rustler::Binary = term.decode()?;
        let point = S::Codec::point_decode(binary.as_slice())
            .map_err(|_| rustler::Error::Atom("deserialization_failed"))?;
        Ok(PublicBridge(point))
    }
}
impl<S: Suite> From<Public<S>> for PublicBridge<S> {
    fn from(public: Public<S>) -> Self {
        PublicBridge(public.0)
    }
}

impl<S: Suite> From<PublicBridge<S>> for Public<S> {
    fn from(bridge: PublicBridge<S>) -> Self {
        Public(bridge.0)
    }
}
