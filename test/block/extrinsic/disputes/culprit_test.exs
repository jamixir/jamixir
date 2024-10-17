defmodule Block.Extrinsic.Disputes.CulpritTest do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes.Culprit
  import Jamixir.Factory

  describe "encode/decode" do
    test "encodes and decodes a fault" do
      fault = build(:culprit)
      encoded = Codec.Encoder.encode(fault)
      {decoded, _} = Culprit.decode(encoded)
      assert fault == decoded
    end
  end
end
