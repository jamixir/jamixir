defmodule CodecVectorsTest do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.{Assurance, Guarantee.WorkResult, Preimage}
  alias Block.Header
  alias Codec.VariableSize
  use ExUnit.Case
  import TestVectorUtil

  describe "encode vectors" do
    tests = [
      {"refine_context", RefinementContext},
      {"assurances_extrinsic", Assurance},
      {"preimages_extrinsic", Preimage},
      {"header_0", Header},
      {"header_1", Header},
      {"work_result_0", WorkResult},
      {"work_result_1", WorkResult},
      {"work_report", WorkReport}
    ]

    Enum.each(tests, fn {file_name, module_name} ->
      @tag file_name: file_name
      @tag module_name: module_name
      test "vector #{file_name} for #{module_name}", %{
        file_name: file_name,
        module_name: module_name
      } do
        assert_correctly_encoded(file_name, module_name)
      end
    end)
  end

  def assert_correctly_encoded(file_name, module) do
    {:ok, json_data} = fetch_and_parse_json(file_name <> ".json", "codec/data")
    expected = fetch_binary(file_name <> ".bin", "codec/data")

    case json_data do
      %{} ->
        object = module.from_json(json_data)
        encoded = Codec.Encoder.encode(object)
        assert encoded == expected

      l when is_list(l) ->
        encoded =
          Codec.Encoder.encode(
            Enum.map(l, &module.from_json(&1))
            |> VariableSize.new()
          )

        assert encoded == expected
    end
  end
end
