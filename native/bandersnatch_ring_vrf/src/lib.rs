use ark_ec_vrfs::suites::bandersnatch::edwards as bandersnatch;
use ark_ec_vrfs::{prelude::ark_serialize, suites::bandersnatch::edwards::RingContext, BaseField};
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};
use bandersnatch::{IetfProof, Input, Output, PcsParams, Public, RingProof, Secret};
use rustler::{Error, NifResult, NifStruct};
use std::marker::PhantomData;
use std::sync::OnceLock;

const RING_SIZE: usize = 1023;
static RING_CTX: OnceLock<RingContext> = OnceLock::new();

// This is the IETF `Prove` procedure output as described in section 2.2
// of the Bandersnatch VRFs specification
#[derive(CanonicalSerialize, CanonicalDeserialize)]
struct IetfVrfSignature {
    output: Output,
    proof: IetfProof,
}

type S = bandersnatch::BandersnatchSha512Ell2;
type PcsCommitment =
    ring_proof::pcs::kzg::commitment::KzgCommitment<<S as ark_ec_vrfs::ring::RingSuite>::Pairing>;

type RingCommitment = ark_ec_vrfs::ring::RingCommitment<S>;

#[derive(Clone, CanonicalSerialize, CanonicalDeserialize, PartialEq, Eq, Debug, NifStruct)]
#[module = "RingCommitment"]
pub struct FixedColumnsCommittedBridge {
    pub points: Vec<PcsCommitment>,
    pub ring_selector: PcsCommitment,
}

impl From<FixedColumnsCommittedBridge> for RingCommitment {
    fn from(bridge: FixedColumnsCommittedBridge) -> Self {
        Self {
            points: bridge.points.try_into().expect("sdfsdf"),
            ring_selector: bridge.ring_selector,
            phantom: Default::default(),
        }
    }
}

impl From<RingCommitment> for FixedColumnsCommittedBridge {
    fn from(commitment: RingCommitment) -> Self {
        Self {
            points: commitment.points.into(),
            ring_selector: commitment.ring_selector,
        }
    }
}

// This is the IETF `Prove` procedure output as described in section 4.2
// of the Bandersnatch VRFs specification
#[derive(CanonicalSerialize, CanonicalDeserialize)]
struct RingVrfSignature {
    output: Output,
    // This contains both the Pedersen proof and actual ring proof.
    proof: RingProof,
}

// Construct VRF Input Point from arbitrary data (section 1.2)
fn vrf_input_point(vrf_input_data: &[u8]) -> Input {
    let point =
        <bandersnatch::BandersnatchSha512Ell2 as ark_ec_vrfs::Suite>::data_to_point(vrf_input_data)
            .unwrap();
    Input::from(point)
}

// Prover actor.
struct Prover {
    pub prover_idx: usize,
    pub secret: Secret,
    pub ring: Vec<Public>,
}

impl Prover {
    pub fn _new(ring: Vec<Public>, prover_idx: usize) -> Self {
        Self {
            prover_idx,
            secret: Secret::from_seed(&prover_idx.to_le_bytes()),
            ring,
        }
    }

    /// Anonymous VRF signature.
    ///
    /// Used for tickets submission.
    pub fn _ring_vrf_sign(&self, vrf_input_data: &[u8], aux_data: &[u8]) -> Vec<u8> {
        use ark_ec_vrfs::ring::Prover as _;

        let input = vrf_input_point(vrf_input_data);
        let output = self.secret.output(input);

        // Backend currently requires the wrapped type (plain affine points)
        let pts: Vec<_> = self.ring.iter().map(|pk| pk.0).collect();

        // Proof construction
        let ring_ctx = RING_CTX.get().expect("ring_context_not_initialized");

        let prover_key = ring_ctx.prover_key(&pts);
        let prover = ring_ctx.prover(prover_key, self.prover_idx);
        let proof = self.secret.prove(input, output, aux_data, &prover);

        // Output and Ring Proof bundled together (as per section 2.2)
        let signature = RingVrfSignature { output, proof };
        let mut buf = Vec::new();
        signature.serialize_compressed(&mut buf).unwrap();
        buf
    }

    /// Non-Anonymous VRF signature.
    ///
    /// Used for ticket claiming during block production.
    /// Not used with Safrole test vectors.
    pub fn _ietf_vrf_sign(&self, vrf_input_data: &[u8], aux_data: &[u8]) -> Vec<u8> {
        use ark_ec_vrfs::ietf::Prover as _;

        let input = vrf_input_point(vrf_input_data);
        let output = self.secret.output(input);

        let proof = self.secret.prove(input, output, aux_data);

        // Output and IETF Proof bundled together (as per section 2.2)
        let signature = IetfVrfSignature { output, proof };
        let mut buf = Vec::new();
        signature.serialize_compressed(&mut buf).unwrap();
        buf
    }
}

// Verifier actor.
struct Verifier {
    pub commitment: RingCommitment,
    pub ring: Vec<Public>,
}

impl Verifier {
    // fn _new(ring: Vec<Public>) -> Self {
    //     // Backend currently requires the wrapped type (plain affine points)
    //     let pts: Vec<_> = ring.iter().map(|pk| pk.0).collect();
    //     let verifier_key = ring_context().verifier_key(&pts);
    //     let commitment = verifier_key.commitment();
    //     Self { ring, commitment }
    // }

    /// Anonymous VRF signature verification.
    ///
    /// Used for tickets verification.
    ///
    /// On success returns the VRF output hash.
    pub fn _ring_vrf_verify(
        &self,
        vrf_input_data: &[u8],
        aux_data: &[u8],
        signature: &[u8],
    ) -> Result<[u8; 32], ()> {
        use ark_ec_vrfs::ring::Verifier as _;

        let signature = RingVrfSignature::deserialize_compressed(signature).unwrap();

        let input = vrf_input_point(vrf_input_data);
        let output = signature.output;

        let ring_ctx = RING_CTX.get().ok_or(())?;

        // The verifier key is reconstructed from the commitment and the constant
        // verifier key component of the SRS in order to verify some proof.
        // As an alternative we can construct the verifier key using the
        // RingContext::verifier_key() method, but is more expensive.
        // In other words, we prefer computing the commitment once, when the keyset changes.
        let verifier_key = ring_ctx.verifier_key_from_commitment(self.commitment.clone());
        let verifier = ring_ctx.verifier(verifier_key);
        if Public::verify(input, output, aux_data, &signature.proof, &verifier).is_err() {
            println!("Ring signature verification failure");
            return Err(());
        }
        println!("Ring signature verified");

        // This truncated hash is the actual value used as ticket-id/score in JAM
        let vrf_output_hash: [u8; 32] = output.hash()[..32].try_into().unwrap();
        println!(" vrf-output-hash: {}", hex::encode(vrf_output_hash));
        Ok(vrf_output_hash)
    }

    /// Non-Anonymous VRF signature verification.
    ///
    /// Used for ticket claim verification during block import.
    /// Not used with Safrole test vectors.
    ///
    /// On success returns the VRF output hash.
    pub fn _ietf_vrf_verify(
        &self,
        vrf_input_data: &[u8],
        aux_data: &[u8],
        signature: &[u8],
        signer_key_index: usize,
    ) -> Result<[u8; 32], ()> {
        use ark_ec_vrfs::ietf::Verifier as _;

        let signature = IetfVrfSignature::deserialize_compressed(signature).unwrap();

        let input = vrf_input_point(vrf_input_data);
        let output = signature.output;

        let public = &self.ring[signer_key_index];
        if public
            .verify(input, output, aux_data, &signature.proof)
            .is_err()
        {
            println!("Ring signature verification failure");
            return Err(());
        }
        println!("Ietf signature verified");

        // This is the actual value used as ticket-id/score
        // NOTE: as far as vrf_input_data is the same, this matches the one produced
        // using the ring-vrf (regardless of aux_data).
        let vrf_output_hash: [u8; 32] = output.hash()[..32].try_into().unwrap();
        println!(" vrf-output-hash: {}", hex::encode(vrf_output_hash));
        Ok(vrf_output_hash)
    }
}
#[rustler::nif]
pub fn create_ring_context(file_contents: Vec<u8>) -> NifResult<()> {
    RING_CTX.get_or_init(|| {
        let pcs_params =
            PcsParams::deserialize_uncompressed_unchecked(&mut &file_contents[..]).unwrap();
        RingContext::from_srs(RING_SIZE, pcs_params).unwrap()
    });
    Ok(())
}

#[rustler::nif]
pub fn create_verifier(ring: Vec<Vec<u8>>) -> NifResult<FixedColumnsCommittedBridge> {
    let pts: Vec<_> = ring
        .iter()
        .map(|hash| vrf_input_point(&hash[..]).0)
        .collect();
    let rc = RING_CTX
        .get()
        .ok_or(Error::Atom("ring_context_not_initialized"))?;

    let verifier_key = rc.verifier_key(&pts);

    let commitment = verifier_key.commitment();

    // let mut buf = Vec::new();
    // commitment.serialize_compressed(&mut buf).unwrap();

    Ok(commitment.into())
}

#[derive(Debug, NifStruct)]
#[module = "Point"]
struct Point {
    x: i32,
    y: i32,
}

#[rustler::nif]
pub fn create_point() -> NifResult<Point> {
    Ok(Point { x: 1, y: 2 })
}

#[rustler::nif]
pub fn read_point(point: Point) -> NifResult<i32> {
    println!("Point: {:?}", point);
    Ok(point.x)
}

rustler::init!("Elixir.BandersnatchRingVrf");
