defmodule TimeMock do
  def validate_timeslot_order(_, _), do: :ok
end

defmodule DisputesTinyTestVectors do
  use ExUnit.Case, async: false
  import Mox
  alias Util.Hash
  setup :verify_on_exit!

  setup_all do
    RingVrf.init_ring_context(Constants.validator_count())
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
      Application.delete_env(:jamixir, Constants)
      Application.delete_env(:jamixir, Util.Time)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    setup do
      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      :ok
    end

    Enum.each(DisputesTestVectors.files_to_test(), fn file_name ->
      @tag file_name: file_name
      @tag :tiny_test_vectors
      test "verify tiny test vectors #{file_name}", %{file_name: file_name} do
        DisputesTestVectors.execute_test(file_name, "disputes/tiny")
      end
    end)
  end
end
