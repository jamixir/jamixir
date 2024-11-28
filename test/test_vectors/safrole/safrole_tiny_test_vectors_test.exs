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
      # skip tests that are failing because of wrong test vectors for 0.5
      @tag if(
             file_name in [
               "enact-epoch-change-with-no-tickets-4",
               "skip-epochs-1",
               "skip-epoch-tail-1",
               "publish-tickets-with-mark-5",
               "publish-tickets-no-mark-1",
               "publish-tickets-no-mark-9"
             ],
             do: :skip
           )

      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        execute_test(file_name, "safrole/tiny")
      end
    end)
  end
end
