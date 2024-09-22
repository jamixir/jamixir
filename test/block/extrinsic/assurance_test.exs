defmodule Block.Extrinsic.AssuranceTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Codec.Encoder

  describe "Assurance encoding" do
    test "encodes an Assurance struct correctly" do
      assurance = build(:assurance)

      encoded = Encoder.encode(assurance)

      expected = <<
        # hash (32 bytes)
        assurance.hash::binary,
        # assurance_values (43 bytes, 344 bits)
        assurance.assurance_values::bitstring,
        # validator_index (2 bytes)
        assurance.validator_index::little-16,
        # signature (64 bytes)
        assurance.signature::binary
      >>

      assert encoded == expected
    end
  end
end
