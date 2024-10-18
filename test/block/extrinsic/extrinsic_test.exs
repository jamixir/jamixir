defmodule Block.ExtrinsicTest do
  alias Block.Extrinsic
  use ExUnit.Case
  import Jamixir.Factory

  defmodule ConstantsMock do
    def validator_count, do: 1
  end

  setup do
    Application.put_env(:jamixir, Constants, ConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)
  end

  describe "encode / decode" do
    test "smoke test" do
      extrinsic = build(:extrinsic, tickets: [build(:ticket_proof)], disputes: build(:disputes))
      encoded = Encodable.encode(extrinsic)
      {decoded, _} = Extrinsic.decode(encoded)
      assert decoded == extrinsic
    end
  end
end
