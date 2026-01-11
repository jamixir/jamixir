defmodule PVM.Authorize.ExecutorTest do
  use ExUnit.Case
  import Jamixir.Factory
  import Codec.Encoder
  alias PVM.Authorize.Executor

  describe "run/4" do
    test "null authorizer" do
      args = <<0::16>>
      # NULL authorizer code
      code = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 6, 51, 7, 51, 8, 50, 0, 21>>
      assert Executor.run(code, args, %{service: 0}) == {<<>>, 3}
    end

    test "invalid code" do
      code = <<0>> <> <<0::20*8>>
      hash = h(code)

      service_account =
        build(:service_account,
          preimage_storage_p: %{hash => code},
          storage: HashedKeysMap.new(%{{hash, byte_size(code)} => [0]})
        )

      wp = build(:work_package, service: 1, authorization_code_hash: hash)
      {:panic, 0} = PVM.authorized(wp, 0, %{1 => service_account})
    end
  end
end
