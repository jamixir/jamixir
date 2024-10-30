defmodule VerdictsFullTestVectors do
  alias Util.Hash
  use ExUnit.Case, async: false
  import Mox
  setup :verify_on_exit!
  @moduletag :full_vectors

  defmodule TimeMock do
    def validate_timeslot_order(_, _), do: :ok
  end

  setup_all do
    RingVrf.init_ring_context(1023)
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    Application.put_env(:jamixir, Util.Time, TimeMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Judgements,
      System.State.CoreReport,
      Block.Extrinsic.Disputes,
      Block.Extrinsic.Disputes.Culprit,
      Block.Extrinsic.Disputes.Fault,
      Block.Extrinsic.Disputes.Judgement,
      Block.Extrinsic.Disputes.Verdict
    ])

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, Util.Time)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  setup do
    stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
      {:ok, %{vrf_signature_output: Hash.zero()}}
    end)

    :ok
  end

  describe "vectors" do
    Enum.each(VerdictsTestVectors.files_to_test(), fn file_name ->
      @tag file_name: file_name
      test "verify full test vectors #{file_name}", %{file_name: file_name} do
        VerdictsTestVectors.execute_test(file_name, "disputes/full")
      end
    end)
  end
end
