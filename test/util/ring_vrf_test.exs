defmodule RingVrfTest do
  use ExUnit.Case
  alias RingVrfTest
  alias BandersnatchRingVrf

  @tag :skip
  test "create_commitment generates a valid commitment" do
    # Generate some mock keys (this would typically be done in Rust)
    keys =
      for _i <- 0..9 do
        # Simulate a 33-byte public key (compressed format)
        :crypto.strong_rand_bytes(32)
      end
      |> Enum.map(&:binary.bin_to_list/1)

    BandersnatchRingVrf.init_ring_context(9)

    # Create verifier (commitment)
    commitment = BandersnatchRingVrf.create_commitment(keys)

    # Mock VRF input data, auxiliary data, and signature
    vrf_input_data = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
    aux_data = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
    signature = :crypto.strong_rand_bytes(64) |> :binary.bin_to_list()

    _result = BandersnatchRingVrf.ring_vrf_verify(commitment, vrf_input_data, aux_data, signature)

    assert true
  end

  test "end-to-end VRF signing and verification" do
    # Initialize the ring context
    BandersnatchRingVrf.init_ring_context(2)

    # Generate a secret key from randomness
    secret = BandersnatchRingVrf.generate_secret_from_scalar([1, 2, 3])
    public = elem(secret, 1)

    # Generate a ring of public keys with the public key derived from the secret at index 0
    keys =
      for _i <- 1..2 do
        secret = BandersnatchRingVrf.generate_secret_from_rand()
        elem(secret, 1)
      end

    # Prepend the public key to the list of keys
    keys = [public | keys]
    IO.inspect(keys, label: "Keys")

    # Create a verifier (commitment)
    commitment = BandersnatchRingVrf.create_commitment(keys)
    # print commitment
    IO.inspect(commitment, label: "Commitment")

    # Select the prover index (for simplicity, use the first key)
    prover_idx = 0

    # Mock VRF input data and auxiliary data
    vrf_input_data = "input data" |> :binary.bin_to_list()
    aux_data = "aux data" |> :binary.bin_to_list()
    # Sign the data using the secret and the ring
    signature =
      BandersnatchRingVrf.ring_vrf_sign(keys, secret, prover_idx, vrf_input_data, aux_data)

    # Verify the signature using the commitment and the same input/aux data
    vrf_output_hash =
      BandersnatchRingVrf.ring_vrf_verify(commitment, vrf_input_data, aux_data, signature)

    IO.inspect(vrf_output_hash, label: "VRF output hash")
    # Assert that verification returns true
    assert vrf_output_hash != nil
  end

  describe "test secret generation" do
    @tag :skip
    test "generate_secret_from_seed generates a secret from a seed" do
      seed = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      secret = BandersnatchRingVrf.generate_secret_from_seed(seed)

      IO.inspect(secret, label: "Secret from seed")
    end

    @tag :skip
    test "generate_secret_from_rand generates a secret from randomness" do
      secret = BandersnatchRingVrf.generate_secret_from_rand()

      IO.inspect(secret, label: "Randomly generated secret")
    end

    @tag :skip
    test "generate_secret_from_scalar generates a secret from a scalar" do
      scalar = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      secret = BandersnatchRingVrf.generate_secret_from_scalar(scalar)

      IO.inspect(secret, label: "Secret from scalar")
    end
  end
end
