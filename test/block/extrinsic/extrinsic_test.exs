defmodule Block.ExtrinsicTest do
  alias Block.Extrinsic
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode / decode" do
    test "smoke test" do
      extrinsic = build(:extrinsic, tickets: [build(:ticket_proof)], disputes: build(:disputes))
      encoded = Encodable.encode(extrinsic)
      {decoded, _} = Extrinsic.decode(encoded)
      assert decoded == extrinsic
    end
  end
end
