use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};
use ark_ec_vrfs::{ScalarField, Secret};
use rand_chacha::rand_core::SeedableRng;
use rustler::NifResult;

use ark_ec_vrfs::prelude::ark_ff::PrimeField;

use crate::rustler_bridges::SecretBridge;

type S = bandersnatch::BandersnatchSha512Ell2;

#[rustler::nif]
fn generate_secret_from_seed(seed: Vec<u8>) -> NifResult<SecretBridge<S>> {
    let secret = Secret::from_seed(&seed);
    Ok(secret.into())
}

#[rustler::nif]
fn generate_secret_from_rand() -> NifResult<SecretBridge<S>> {
    let mut rng = rand_chacha::ChaCha20Rng::from_entropy();
    let secret = Secret::from_rand(&mut rng);
    Ok(secret.into())
}

#[rustler::nif]
fn generate_secret_from_scalar(scalar_bytes: Vec<u8>) -> NifResult<SecretBridge<S>> {
    let scalar = ScalarField::<S>::from_le_bytes_mod_order(&scalar_bytes[..]);
    let secret = Secret::from_scalar(scalar);
    Ok(secret.into())
}
