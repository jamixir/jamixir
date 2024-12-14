use ark_ec_vrfs::ring::RingSuite;
use ark_ec_vrfs::suites::bandersnatch::edwards::{self as bandersnatch};

pub type PcsCommitment<S> = ring_proof::pcs::kzg::commitment::KzgCommitment<<S as RingSuite>::Pairing>;
pub type Bandersnatch = bandersnatch::BandersnatchSha512Ell2;
pub type VerifierKey<S> = ark_ec_vrfs::ring::VerifierKey<S>;