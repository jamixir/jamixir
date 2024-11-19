defmodule DisputesTinyTestVectors do
  use ExUnit.Case, async: false
  import Mox
  alias Util.Hash
  import DisputesTestVectors
  setup :verify_on_exit!
  @moduletag :tiny_test_vectors

  setup_all(do: setup_all())

  describe "vectors" do
    setup do
      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      :ok
    end

    Enum.each(files_to_test(), fn file_name ->
      @tag file_name: file_name
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        execute_test(file_name, "disputes/tiny")
      end
    end)
  end
end
