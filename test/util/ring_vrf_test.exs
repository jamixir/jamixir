defmodule RingVrfTest do
  use ExUnit.Case
  alias RingVrfTest
  alias BandersnatchRingVrf

  defp gen_keys(public_key_index, count) do
    # Generate a secret key from randomness
    secret = BandersnatchRingVrf.generate_secret_from_rand()
    public = elem(secret, 1)

    # Generate a ring of public keys
    keys =
      for _i <- 1..(count - 1) do
        secret = BandersnatchRingVrf.generate_secret_from_rand()
        elem(secret, 1)
      end

    # Insert the public key at the specified position
    keys = List.insert_at(keys, public_key_index, public)

    {keys, secret}
  end

  defp init_ring_context_and_gen_keys(count), do: init_ring_context_and_gen_keys(0, count)

  defp init_ring_context_and_gen_keys(public_key_index, count) do
    BandersnatchRingVrf.init_ring_context(count)
    gen_keys(public_key_index, count)
  end

  describe "end-to-end VRF signing and verification" do
    test "verification succeeds with larger number of keys and public key in the middle" do
      validator_index = 100
      {keys, secret} = init_ring_context_and_gen_keys(validator_index, 1023)

      # Create a verifier (commitment)
      commitment = BandersnatchRingVrf.create_commitment(keys)

      # Sign with original message
      signature =
        BandersnatchRingVrf.ring_vrf_sign(keys, secret, validator_index, "input data", "aux data")

      # Verify with correct commitment
      %RingVRF.VerificationResult{verified: verified, vrf_output_hash: vrf_output_hash} =
        BandersnatchRingVrf.ring_vrf_verify(
          commitment,
          "input data",
          "aux data",
          signature
        )

      assert verified
      assert byte_size(vrf_output_hash) == 32
    end

    test "succeeds with a simple ring of size 5" do
      # Initialize the ring context
      BandersnatchRingVrf.init_ring_context(5)

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
      vrf_input_data = "input data"
      aux_data = "aux data"
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
      assert byte_size(vrf_output_hash) == 32
    end
  end

  describe "failure scenarios" do
    test "verification fails with altered message" do
      # Initialize the ring context

      {keys, secret} = init_ring_context_and_gen_keys(2)

      # Create a verifier (commitment)
      commitment = BandersnatchRingVrf.create_commitment(keys)

      # Sign with original message
      signature =
        BandersnatchRingVrf.ring_vrf_sign(keys, secret, 0, "original message", "aux data")

      # Verify with altered message
      %RingVRF.VerificationResult{verified: verified} =
        BandersnatchRingVrf.ring_vrf_verify(
          commitment,
          "altered message",
          "aux data",
          signature
        )

      assert not verified
    end

    test "verification fails with altered commitment" do
      {keys, secret} = init_ring_context_and_gen_keys(2)
      BandersnatchRingVrf.create_commitment(keys)
      signature = BandersnatchRingVrf.ring_vrf_sign(keys, secret, 0, "input data", "aux data")

      # Alter commitment by generating a new one
      altered_commitment = BandersnatchRingVrf.create_commitment(Enum.reverse(keys))

      %RingVRF.VerificationResult{verified: verified} =
        BandersnatchRingVrf.ring_vrf_verify(
          altered_commitment,
          "input data",
          "aux data",
          signature
        )

      assert not verified
    end

    test "verification fails with wrong prover index" do
      {keys, secret} = init_ring_context_and_gen_keys(6, 20)

      # Create a verifier (commitment)
      commitment = BandersnatchRingVrf.create_commitment(keys)

      # Sign with original message but use the wrong prover index
      signature = BandersnatchRingVrf.ring_vrf_sign(keys, secret, 8, "input data", "aux data")

      # Verify with correct commitment
      %RingVRF.VerificationResult{verified: verified} =
        BandersnatchRingVrf.ring_vrf_verify(
          commitment,
          "input data",
          "aux data",
          signature
        )

      assert not verified
    end

    test "verification fails with altered auxiliary data" do
      {keys, secret} = init_ring_context_and_gen_keys(2)
      commitment = BandersnatchRingVrf.create_commitment(keys)

      signature =
        BandersnatchRingVrf.ring_vrf_sign(keys, secret, 0, "input data", "original aux data")

      # Verify with altered auxiliary data
      %RingVRF.VerificationResult{verified: verified} =
        BandersnatchRingVrf.ring_vrf_verify(
          commitment,
          "input data",
          "altered aux data",
          signature
        )

      assert not verified
    end
  end

  describe "test secret generation" do
    test "generate_secret_from_seed generates a secret from a seed" do
      seed = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      _secret = BandersnatchRingVrf.generate_secret_from_seed(seed)
    end

    test "generate_secret_from_rand generates a secret from randomness" do
      _secret = BandersnatchRingVrf.generate_secret_from_rand()
    end

    test "generate_secret_from_scalar generates a secret from a scalar" do
      scalar = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      _secret = BandersnatchRingVrf.generate_secret_from_scalar(scalar)
    end
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
