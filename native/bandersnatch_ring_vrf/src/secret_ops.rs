use ark_ec_vrfs::{
    reexports::ark_ff::PrimeField, suites::bandersnatch::BandersnatchSha512Ell2, ScalarField,
    Secret,
};
use rand_chacha::rand_core::SeedableRng;
use rustler::NifResult;

use crate::rustler_bridges::{PublicBridge, SecretBridge};

type S = BandersnatchSha512Ell2;

#[rustler::nif]
fn generate_secret_from_seed(seed: Vec<u8>) -> NifResult<(SecretBridge<S>, PublicBridge<S>)> {
    let secret = Secret::from_seed(&seed);
    let public = secret.public();
    Ok((secret.into(), public.into()))
}

#[rustler::nif]
fn generate_secret_from_rand() -> NifResult<(SecretBridge<S>, PublicBridge<S>)> {
    let mut rng = rand_chacha::ChaCha20Rng::from_entropy();
    let secret = Secret::from_rand(&mut rng);
    let public = secret.public();
    Ok((secret.into(), public.into()))
}

#[rustler::nif]
fn generate_secret_from_scalar(
    scalar_bytes: Vec<u8>,
) -> NifResult<(SecretBridge<S>, PublicBridge<S>)> {
    let scalar = ScalarField::<S>::from_le_bytes_mod_order(&scalar_bytes[..]);
    let secret = Secret::from_scalar(scalar);
    let public = secret.public();
    Ok((secret.into(), public.into()))
}
