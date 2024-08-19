defmodule RingVrfTest do
  use ExUnit.Case
  alias RingVrfTest

  @tag :skip
  test "create_verifier generates a valid commitment" do
    # Generate some mock keys (this would typically be done in Rust)
    keys =
      for i <- 0..9 do
        # Simulate a 33-byte public key (compressed format)
        :crypto.strong_rand_bytes(32)
      end
      |> Enum.map(&:binary.bin_to_list/1)

    # Call the Rust NIF
    commitment = BandersnatchRingVrf.create_verifier(keys)

    # Check that the commitment is a non-empty binary
    assert is_binary(commitment)
    assert byte_size(commitment) > 0

    # Optionally, if you know the expected size, check for it:
    # assert byte_size(commitment) == expected_size
  end
end
