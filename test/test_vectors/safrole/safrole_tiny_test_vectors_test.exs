defmodule SafroleTinyTestVectors do
  use ExUnit.Case
  import Mox
  import SafroleTestVectors

  setup :verify_on_exit!
  @moduletag :tiny_test_vectors

  setup_all(do: setup_all())

  describe "vectors" do
    Enum.each(files(), fn file_name ->
      @tag file_name: file_name
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        execute_test(file_name, "safrole/tiny")
      end
    end)
  end
end
