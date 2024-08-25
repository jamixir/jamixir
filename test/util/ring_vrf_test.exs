defmodule RingVrfTest do
  use ExUnit.Case
  alias RingVrfTest
  alias BandersnatchRingVrf

  test "create_commitment generates a valid commitment" do
    # Generate some mock keys (this would typically be done in Rust)
    keys =
      for _i <- 0..9 do
        secret = BandersnatchRingVrf.generate_secret_from_rand()
        elem(secret, 1)
      end


    BandersnatchRingVrf.init_ring_context(9)

    # Create verifier (commitment)
    commitment = BandersnatchRingVrf.create_commitment(keys)
    assert length(commitment.points) == 2

  end

  test "end-to-end VRF signing and verification" do
    # Initialize the ring context
    BandersnatchRingVrf.init_ring_context(2)

    # Generate a secret key from randomness
    secret = BandersnatchRingVrf.generate_secret_from_rand()
    public = elem(secret, 1)

    # Generate a ring of public keys with the public key derived from the secret at index 0
    keys =
      for _i <- 1..2 do
        secret = BandersnatchRingVrf.generate_secret_from_rand()
        elem(secret, 1)
      end

    # Prepend the public key to the list of keys
    keys = [public | keys]

    # Create a verifier (commitment)
    commitment = BandersnatchRingVrf.create_commitment(keys)
    # print commitment

    # Select the prover index (for simplicity, use the first key)
    prover_idx = 0

    # Mock VRF input data and auxiliary data
    vrf_input_data = "input data" |> :binary.bin_to_list()
    aux_data = "aux data" |> :binary.bin_to_list()
    # Sign the data using the secret and the ring
    signature =
      BandersnatchRingVrf.ring_vrf_sign(keys, secret, prover_idx, vrf_input_data, aux_data)

    # Verify the signature using the commitment and the same input/aux data
    %RingVRF.VerificationResult{
      verified: verified,
      vrf_output_hash: vrf_output_hash
    } =
      BandersnatchRingVrf.ring_vrf_verify(commitment, vrf_input_data, aux_data, signature)

    # Assert that verification returns true
    assert verified
    assert length(vrf_output_hash) == 32
  end

  describe "test secret generation" do
    test "generate_secret_from_seed generates a secret from a seed" do
      seed = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      secret = BandersnatchRingVrf.generate_secret_from_seed(seed)
    end

    test "generate_secret_from_rand generates a secret from randomness" do
      secret = BandersnatchRingVrf.generate_secret_from_rand()
    end

    test "generate_secret_from_scalar generates a secret from a scalar" do
      scalar = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      secret = BandersnatchRingVrf.generate_secret_from_scalar(scalar)
    end
  end
end
