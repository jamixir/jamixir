defmodule CodecVectorsTest do
  alias Block.Header
  alias Block.Extrinsic.Assurance
  alias Codec.VariableSize
  use ExUnit.Case
  import TestVectorUtil

  describe "encode vectors" do
    test "refine context" do
      assert_correctly_encoded("refine_context", RefinementContext)
    end

    test "assurances extrinsic" do
      assert_correctly_encoded("assurances_extrinsic", Assurance)
    end

    test "header no tickets mark" do
      assert_correctly_encoded("header_0", Header)
    end

    test "header with tickets mark" do
      assert_correctly_encoded("header_1", Header)
    end
  end

  def assert_correctly_encoded(file_name, module) do
    {:ok, json_data} = fetch_and_parse_json(file_name <> ".json", "codec/data")
    expected = fetch_binary(file_name <> ".bin", "codec/data")

    case json_data do
      %{} ->
        object = module.from_json(Utils.atomize_keys(json_data))
        encoded = Codec.Encoder.encode(object)

        if encoded != expected do
          IO.inspect(object)
        end

        assert encoded == expected

      l when is_list(l) ->
        encoded =
          Codec.Encoder.encode(
            Enum.map(l, &module.from_json(Utils.atomize_keys(&1)))
            |> VariableSize.new()
          )

        assert encoded == expected
    end
  end
end
