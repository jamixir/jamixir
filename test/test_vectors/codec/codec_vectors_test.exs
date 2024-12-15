defmodule CodecVectorsTest do
  use Codec.Encoder
  use ExUnit.Case
  import TestVectorUtil

  define_repo_variables()

  describe "encode vectors" do
    Enum.each(CodecVectors.tests(), fn {file_name, module_name} ->
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
    {:ok, json_data} =
      fetch_and_parse_json("#{file_name}.json", "codec/data", @owner, @repo, @branch)

    expected = fetch_binary("#{file_name}.bin", "codec/data", @owner, @repo, @branch)

    case json_data do
      %{} ->
        object = module.from_json(json_data)
        encoded = Encodable.encode(object)
        assert encoded == expected

        {decoded, _} = module.decode(expected)
        assert decoded == object

      l when is_list(l) ->
        encoded = e(vs(for o <- l, do: module.from_json(o)))
        assert encoded == expected
    end
  end
end
