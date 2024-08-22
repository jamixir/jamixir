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

    # Call the Rust NIF
    commitment = BandersnatchRingVrf.create_verifier(keys)
    BandersnatchRingVrf.read_commitment(commitment)
    # assert length(commitment) == 144
  end
end
