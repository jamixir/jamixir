defmodule RingVrfTest do
  use ExUnit.Case
  alias RingVrfTest
  alias RingVrf

  defp gen_keys(public_key_index, count) do
    # Generate a secret key from randomness
    {secret, public} = RingVrf.generate_secret_from_rand()

    # Generate a ring of public keys
    keys =
      for _i <- 1..(count - 1) do
        secret = RingVrf.generate_secret_from_rand()
        elem(secret, 1)
      end

    # Insert the public key at the specified position
    keys = List.insert_at(keys, public_key_index, public)

    {keys, secret}
  end

  defp init_ring_context_and_gen_keys(count), do: init_ring_context_and_gen_keys(0, count)

  defp init_ring_context_and_gen_keys(public_key_index, count) do
    RingVrf.init_ring_context(count)
    gen_keys(public_key_index, count)
  end

  describe "end-to-end VRF signing and verification" do
    test "verification succeeds with larger number of keys and public key in the middle" do
      validator_index = 100
      {keys, secret} = init_ring_context_and_gen_keys(validator_index, 1023)
      commitment = RingVrf.create_commitment(keys)

      {signature, output} =
        RingVrf.ring_vrf_sign(keys, secret, validator_index, "context", "message")

      assert {:ok, vrf_output_hash} =
               RingVrf.ring_vrf_verify(
                 commitment,
                 "context",
                 "message",
                 signature
               )

      assert vrf_output_hash == output
    end

    test "succeeds with a simple ring of size 5" do
      {keys, secret} = init_ring_context_and_gen_keys(5)
      commitment = RingVrf.create_commitment(keys)

      {signature, output} =
        RingVrf.ring_vrf_sign(keys, secret, 0, "context", "message")

      assert {:ok, vrf_output_hash} =
               RingVrf.ring_vrf_verify(
                 commitment,
                 "context",
                 "message",
                 signature
               )

      assert vrf_output_hash == output
      assert byte_size(vrf_output_hash) == 32
    end
  end

  describe "failure scenarios" do
    test "verification fails with altered message" do
      {keys, secret} = init_ring_context_and_gen_keys(2)
      commitment = RingVrf.create_commitment(keys)

      {signature, _output} =
        RingVrf.ring_vrf_sign(keys, secret, 0, "original context", "message")

      assert {:error, :verification_failed} =
               RingVrf.ring_vrf_verify(
                 commitment,
                 "altered context",
                 "message",
                 signature
               )
    end

    test "verification fails with altered commitment" do
      {keys, secret} = init_ring_context_and_gen_keys(2)

      {signature, _output} =
        RingVrf.ring_vrf_sign(keys, secret, 0, "input data", "aux data")

      altered_commitment = RingVrf.create_commitment(Enum.reverse(keys))

      assert {:error, :verification_failed} =
               RingVrf.ring_vrf_verify(
                 altered_commitment,
                 "context",
                 "message",
                 signature
               )
    end

    test "verification fails with wrong prover index" do
      {keys, secret} = init_ring_context_and_gen_keys(6, 20)
      commitment = RingVrf.create_commitment(keys)

      {signature, _output} =
        RingVrf.ring_vrf_sign(keys, secret, 8, "context", "message")

      assert {:error, :verification_failed} =
               RingVrf.ring_vrf_verify(
                 commitment,
                 "context",
                 "message",
                 signature
               )
    end

    test "verification fails with altered auxiliary data" do
      {keys, secret} = init_ring_context_and_gen_keys(2)
      commitment = RingVrf.create_commitment(keys)

      {signature, _output} =
        RingVrf.ring_vrf_sign(keys, secret, 0, "context", "original message")

      assert {:error, :verification_failed} =
               RingVrf.ring_vrf_verify(
                 commitment,
                 "context",
                 "altered message",
                 signature
               )
    end
  end

  describe "test secret generation" do
    test "generate_secret_from_seed generates a secret from a seed" do
      seed = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      _secret = RingVrf.generate_secret_from_seed(seed)
    end

    test "generate_secret_from_rand generates a secret from randomness" do
      _secret = RingVrf.generate_secret_from_rand()
    end

    test "generate_secret_from_scalar generates a secret from a scalar" do
      scalar = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      _secret = RingVrf.generate_secret_from_scalar(scalar)
    end
  end

  describe "ietf_vrf_sign and ietf_vrf_verify" do
    test "simple sanity test: create key, sign something, get something back" do
      {_, secret} = init_ring_context_and_gen_keys(1)
      {signature, output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      assert byte_size(signature) == 96
      assert byte_size(output) == 32
    end

    test "key sign and verify - all ok" do
      signer_key_index = 2
      {keys, secret} = init_ring_context_and_gen_keys(signer_key_index, 7)

      {signature, _output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      # Verify the signature
      result =
        RingVrf.ietf_vrf_verify(
          keys,
          "context",
          "message",
          signature,
          signer_key_index
        )

      assert {:ok, vrf_output_hash} = result
      assert byte_size(vrf_output_hash) == 32
    end
  end

  describe "ietf_vrf error scenarios" do
    test "verification fails with invalid signature" do
      {keys, _secret} = init_ring_context_and_gen_keys(8)
      # Provide an invalid/corrupted signature
      result =
        RingVrf.ietf_vrf_verify(
          keys,
          "context",
          "message",
          # invalid signature
          <<1, 2, 3>>,
          0
        )

      assert {:error, :invalid_signature} = result
    end

    test "verification fails with mismatched public key" do
      {keys, secret} = init_ring_context_and_gen_keys(8)
      {signature, _output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      # Alter the key index
      altered_key_index = 1

      result =
        RingVrf.ietf_vrf_verify(
          keys,
          "context",
          "message",
          signature,
          altered_key_index
        )

      assert {:error, :verification_failed} = result
    end

    test "verification fails with altered context" do
      {keys, secret} = init_ring_context_and_gen_keys(50)
      {signature, _output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      result =
        RingVrf.ietf_vrf_verify(
          keys,
          "altered context",
          "message",
          signature,
          0
        )

      assert {:error, :verification_failed} = result
    end

    test "verification fails with altered message" do
      {keys, secret} = init_ring_context_and_gen_keys(4)
      {signature, _output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      result =
        RingVrf.ietf_vrf_verify(
          keys,
          "context",
          "altered message",
          signature,
          0
        )

      assert {:error, :verification_failed} = result
    end
  end

  describe "Context influence on output, message doesn't " do
    test "ring signature output changes with context but not with message" do
      {keys, secret} = init_ring_context_and_gen_keys(4)

      {_sig1, out1} = RingVrf.ring_vrf_sign(keys, secret, 0, "context1", "message")
      {_sig2, out2} = RingVrf.ring_vrf_sign(keys, secret, 0, "context2", "message")
      {_sig3, out3} = RingVrf.ring_vrf_sign(keys, secret, 0, "context1", "diff message")

      assert out1 != out2
      assert out1 == out3
    end

    test "ietf signature output changes with context but not with message" do
      {_, secret} = init_ring_context_and_gen_keys(1)

      {_sig1, out1} = RingVrf.ietf_vrf_sign(secret, "context1", "message")
      {_sig1, out2} = RingVrf.ietf_vrf_sign(secret, "context2", "message")
      {_sig1, out3} = RingVrf.ietf_vrf_sign(secret, "context1", "diff message")

      assert out1 != out2
      assert out1 == out3
    end
  end
end
