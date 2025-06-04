defmodule Block.Extrinsic.Disputes.JudgementTest do
  alias Block.Extrinsic.Disputes.Judgement
  use ExUnit.Case
  import Codec.Encoder
  import Jamixir.Factory

  describe "encode/decode" do
    test "encode and decode smoke test" do
      judgement = build(:judgement)
      {decoded, _} = Judgement.decode(e(judgement))
      assert decoded == judgement
    end
  end
end
