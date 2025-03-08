defmodule DisputesTinyTestVectors do
  use ExUnit.Case
  import Mox
  import DisputesTestVectors
  import TestVectorUtil
  import TestHelper

  setup :verify_on_exit!

  setup do
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [
      :validate,
      System.State.Judgements,
      System.State.CoreReport,
      Block.Extrinsic.Disputes,
      Block.Extrinsic.Disputes.Culprit,
      Block.Extrinsic.Disputes.Fault,
      Block.Extrinsic.Disputes.Judgement,
      Block.Extrinsic.Disputes.Verdict,
      Block.Extrinsic.Guarantee.WorkReport
    ])

    mock_header_seal()
    mock_accumulate()

    on_exit(fn ->
      Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  describe "vectors" do
    define_vector_tests("disputes")
  end
end
