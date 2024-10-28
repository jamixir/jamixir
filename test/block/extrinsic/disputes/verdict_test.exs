defmodule Block.Extrinsic.Disputes.VerdictTest do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes.Verdict
  import Jamixir.Factory
  import TestHelper

  setup_validators(1)

  describe "encode/decode" do
    test "encodes and decodes a verdict" do
      verdict = build(:verdict)
      encoded = Codec.Encoder.encode(verdict)
      {decoded, _} = Verdict.decode(encoded)
      assert verdict == decoded
    end
  end
end
