defmodule CodecVectorsTest do
  alias Block.Extrinsic
  alias Block.Extrinsic.{Disputes, Guarantee, TicketProof}
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.{Assurance, Guarantee.WorkResult, Preimage}
  alias Block.Header
  alias Codec.VariableSize
  use ExUnit.Case
  import TestVectorUtil

  defmodule ConstantsMock do
    def core_count, do: 2
    def validator_count, do: 6
    def epoch_length, do: 12
  end

  tests = [
    {"assurances_extrinsic", Assurance},
    {"block", Block},
    {"disputes_extrinsic", Disputes},
    {"extrinsic", Extrinsic},
    {"guarantees_extrinsic", Guarantee},
    {"header_0", Header},
    {"header_1", Header},
    {"preimages_extrinsic", Preimage},
    {"refine_context", RefinementContext},
    {"tickets_extrinsic", TicketProof},
    # {"work_item", WorkItem},
    {"work_report", WorkReport},
    {"work_result_0", WorkResult},
    {"work_result_1", WorkResult}
  ]

  setup_all do
    Application.put_env(:jamixir, Constants, ConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)
  end

  describe "encode vectors" do
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
        encoded = Encodable.encode(object)
        assert encoded == expected

        {decoded, _} = module.decode(expected)
        assert decoded == object

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
