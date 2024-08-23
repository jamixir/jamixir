mod commitment;
mod ring_context;
mod secret_ops;
mod vrf_operations;
mod rustler_bridges;

#[rustler::nif]
fn ring_vrf_sign(
    ring: Vec<Vec<u8>>,      // Vector of public keys as Vec<u8>
    secret: Secret,          // Secret key
    prover_idx: usize,       // Index of the prover
    vrf_input_data: Vec<u8>, // VRF input data
    aux_data: Vec<u8>,       // Auxiliary data
) -> NifResult<Vec<u8>> {
    use ark_ec_vrfs::ring::Prover as _;

    let input = vrf_input_point(&vrf_input_data);
    let output = secret.output(input);

    let pts: Vec<_> = ring
        .iter()
        .map(|hash| vrf_input_point(&hash[..]).0)
        .collect();

    let ring_ctx = RING_CTX
        .get()
        .ok_or(Error::Atom("ring_context_not_initialized"))?;

    let prover_key = ring_ctx.prover_key(&pts);
    let prover = ring_ctx.prover(prover_key, prover_idx);
    let proof = secret.prove(input, output, aux_data, &prover);

    // Output and Ring Proof bundled together (as per section 2.2)
    let signature = RingVrfSignature { output, proof };
    let mut buf = Vec::new();
    signature.serialize_compressed(&mut buf).unwrap();

    Ok(buf)
}

rustler::init!("Elixir.BandersnatchRingVrf");
