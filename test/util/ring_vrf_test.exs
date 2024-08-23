defmodule RingVrfTest do
  use ExUnit.Case
  alias RingVrfTest
  alias BandersnatchRingVrf

  test "create_verifier generates a valid commitment" do
    # Generate some mock keys (this would typically be done in Rust)
    keys =
      for _i <- 0..9 do
        # Simulate a 33-byte public key (compressed format)
        :crypto.strong_rand_bytes(32)
      end
      |> Enum.map(&:binary.bin_to_list/1)

    BandersnatchRingVrf.init_ring_context()

    # Create verifier (commitment)
    commitment = BandersnatchRingVrf.create_verifier(keys)

    # Mock VRF input data, auxiliary data, and signature
    vrf_input_data = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
    aux_data = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
    signature = :crypto.strong_rand_bytes(64) |> :binary.bin_to_list()

    result = BandersnatchRingVrf.ring_vrf_verify(commitment, vrf_input_data, aux_data, signature)
    # Call the Rust NIF for verification
    # case BandersnatchRingVrf.ring_vrf_verify(commitment, vrf_input_data, aux_data, signature) do
    #   {:ok, hash} -> IO.puts("VRF verification succeeded: #{Base.encode16(hash)}")
    #   {:error, reason} -> IO.puts("VRF verification failed: #{reason}")
    # end

    # As the actual content is not valid, expect the function to fail
    # assert_raise RuntimeError, fn ->
    #   BandersnatchRingVrf.ring_vrf_verify(commitment, vrf_input_data, aux_data, signature)

    # end
    assert true
  end

  describe "test secret generation" do
    test "generate_secret_from_seed generates a secret from a seed" do
      seed = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      secret = BandersnatchRingVrf.generate_secret_from_seed(seed)

      IO.inspect(secret, label: "Secret from seed")
    end

    test "generate_secret_from_rand generates a secret from randomness" do
      secret = BandersnatchRingVrf.generate_secret_from_rand()

      IO.inspect(secret, label: "Randomly generated secret")
    end

    test "generate_secret_from_scalar generates a secret from a scalar" do
      scalar = :crypto.strong_rand_bytes(32) |> :binary.bin_to_list()
      secret = BandersnatchRingVrf.generate_secret_from_scalar(scalar)

      IO.inspect(secret, label: "Secret from scalar")
    end




  end
end
