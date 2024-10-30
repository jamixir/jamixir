defmodule SafroleFullTestVectors do
  use ExUnit.Case
  import Mox
  import TestVectorUtil
  alias SafroleTests
  setup :verify_on_exit!
  @moduletag :full_vectors

  @path "safrole/full"

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
    test "verify epoch length" do
      assert Constants.epoch_length() == 600
    end

    Enum.each(SafroleTests.files(), fn file_name ->
      @tag file_name: file_name
      test "verify full test vectors #{file_name}", %{file_name: file_name} do
        {:ok, json_data} = fetch_and_parse_json(file_name <> ".json", @path)

        stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
          {:ok, %{vrf_signature_output: json_data[:input][:entropy] |> JsonDecoder.from_json()}}
        end)

        assert_expected_results(json_data, SafroleTests.tested_keys(), file_name)
      end
    end)
  end
end
