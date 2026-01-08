defmodule PVM.Authorize.ExecutorTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias PVM.Authorize.Executor

  describe "run/4" do
    test "null authorizer" do
      args = <<0::16>>
      # NULL authorizer code
      code = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 6, 51, 7, 51, 8, 50, 0, 21>>
      assert Executor.run(code, args, %{service: 0}) == {<<>>, 3}
    end
  end
end
