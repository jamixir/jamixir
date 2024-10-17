defmodule Block.Extrinsic.Disputes.VerdictTest do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes.Verdict
  import Jamixir.Factory

  defmodule ConstantsMock do
    def validator_count, do: 1
  end

  setup_all do
    Application.put_env(:jamixir, Constants, ConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)
  end

  describe "encode/decode" do
    test "encodes and decodes a verdict" do
      verdict = build(:verdict)
      encoded = Codec.Encoder.encode(verdict)
      {decoded, _} = Verdict.decode(encoded)
      assert verdict == decoded
    end
  end
end
