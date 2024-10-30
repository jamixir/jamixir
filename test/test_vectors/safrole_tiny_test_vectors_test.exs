defmodule ConstantsMock do
  def epoch_length, do: 12
  def ticket_submission_end, do: 10
end

defmodule SafroleTinyTestVectors do
  use ExUnit.Case, async: false
  import Mox
  setup :verify_on_exit!

  setup_all do
    RingVrf.init_ring_context(6)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, Constants, ConstantsMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Safrole,
      System.Validators.Safrole,
      Block.Extrinsic.TicketProof
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, Constants)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    Enum.each(SafroleTestVectors.files(), fn file_name ->
      @tag file_name: file_name
      @tag :tiny_test_vectors
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        SafroleTestVectors.execute_test(file_name, "safrole/tiny")
      end
    end)
  end
end
