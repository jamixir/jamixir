defmodule Block.Extrinsic.Disputes.FaultTest do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes.Fault
  import Jamixir.Factory

  describe "encode/decode" do
    test "encodes and decodes a fault" do
      fault = build(:fault, vote: false)
      encoded = Codec.Encoder.encode(fault)
      {decoded, _} = Fault.decode(encoded)
      assert fault == decoded
    end
  end
end
