defmodule SafroleFullTestVectors do
  use ExUnit.Case
  import Mox
  setup :verify_on_exit!
  @moduletag :full_vectors

  setup_all do
    RingVrf.init_ring_context(1023)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Safrole,
      System.Validators.Safrole,
      Block.Extrinsic.TicketProof
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    Enum.each(SafroleTestVectors.files(), fn file_name ->
      @tag file_name: file_name
      test "verify full test vectors #{file_name}", %{file_name: file_name} do
        SafroleTestVectors.execute_test(file_name, "safrole/full")
      end
    end)
  end
end
