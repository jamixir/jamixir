defmodule RingVrfTest do
  use ExUnit.Case
  alias RingVrf
  alias RingVrfTest
  alias Util.Hash
  use Sizes

  defp gen_keys(public_key_index, count) do
    # Generate a secret key from randomness
    {keypair, public} = RingVrf.generate_secret_from_rand()

    # Generate a ring of public keys
    keys =
      for _i <- 1..(count - 1) do
        {_, pubkey} = RingVrf.generate_secret_from_rand()
        pubkey
      end

    # Insert the public key at the specified position
    keys = List.insert_at(keys, public_key_index, public)

    {keys, keypair}
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
      assert byte_size(vrf_output_hash) == @hash_size
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
      seed = Hash.random() |> :binary.bin_to_list()
      _secret = RingVrf.generate_secret_from_seed(seed)
    end

    test "generate_secret_from_rand generates a secret from randomness" do
      _secret = RingVrf.generate_secret_from_rand()
    end

    test "generate_secret_from_scalar generates a secret from a scalar" do
      scalar = Hash.random() |> :binary.bin_to_list()
      _secret = RingVrf.generate_secret_from_scalar(scalar)
    end
  end

  describe "ietf_vrf_sign and ietf_vrf_verify" do
    test "simple sanity test: create key, sign something, get something back" do
      {_, keypair} = init_ring_context_and_gen_keys(1)
      {signature, output} = RingVrf.ietf_vrf_sign(keypair, "context", "message")

      assert byte_size(signature) == 96
      assert byte_size(output) == @hash_size
    end

    test "key sign and verify - all ok" do
      {keys, keypair} = init_ring_context_and_gen_keys(2, 7)
      {signature, output} = RingVrf.ietf_vrf_sign(keypair, "context", "message")
      {:ok, ^output} = RingVrf.ietf_vrf_verify(Enum.at(keys, 2), "context", "message", signature)

      assert byte_size(output) == @hash_size
    end

    test "key sign from seed - all ok" do
      {keypair, pub} = RingVrf.generate_secret_from_seed(<<0::256>> |> :binary.bin_to_list())
      {signature, output} = RingVrf.ietf_vrf_sign(keypair, "context", "message")
      {:ok, ^output} = RingVrf.ietf_vrf_verify(pub, "context", "message", signature)
    end

    test "key sign from alice key" do
      %{bandersnatch: pub, bandersnatch_priv: priv} =
        JsonDecoder.from_json(JsonReader.read("priv/alice.json"))

      keypair = {priv, pub}
      {signature, output} = RingVrf.ietf_vrf_sign(keypair, "context", "message")
      {:ok, ^output} = RingVrf.ietf_vrf_verify(pub, "context", "message", signature)
    end
  end

  describe "ietf_vrf error scenarios" do
    test "verification fails with invalid signature" do
      {[key | _], _secret} = init_ring_context_and_gen_keys(8)
      # Provide an invalid/corrupted signature
      result =
        RingVrf.ietf_vrf_verify(
          key,
          "context",
          "message",
          # invalid signature
          <<1, 2, 3>>
        )

      assert {:error, :invalid_signature} = result
    end

    test "verification fails with mismatched public key" do
      {[_, k2 | _], secret} = init_ring_context_and_gen_keys(8)
      {signature, _output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      result =
        RingVrf.ietf_vrf_verify(k2, "context", "message", signature)

      assert {:error, :verification_failed} = result
    end

    test "verification fails with altered context" do
      {[key | _], secret} = init_ring_context_and_gen_keys(50)
      {signature, _output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      result =
        RingVrf.ietf_vrf_verify(key, "altered context", "message", signature)

      assert {:error, :verification_failed} = result
    end

    test "verification fails with altered message" do
      {[key | _], secret} = init_ring_context_and_gen_keys(4)
      {signature, _output} = RingVrf.ietf_vrf_sign(secret, "context", "message")

      result =
        RingVrf.ietf_vrf_verify(key, "context", "altered message", signature)

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

  describe "sign with test keys" do
    test "sign with test" do
      {:ok, keys} = KeyManager.load_keys("test/keys/0.json")
      output = RingVrf.ietf_vrf_output({keys.bandersnatch_priv, keys.bandersnatch}, <<1>>)
      assert is_binary(output)
    end
  end
end
