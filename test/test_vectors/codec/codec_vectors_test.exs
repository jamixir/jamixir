defmodule CodecVectorsTest do
  use Codec.Encoder
  use ExUnit.Case
  import TestVectorUtil

  define_repo_variables()

  #   for vector_type <- [:tiny, :full] do
  #   for file_name <- files_to_test() do
  #     @tag file_name: file_name
  #     @tag vector_type: vector_type
  #     @tag :"#{vector_type}_vectors"
  #     test "verify #{unquote(type)} #{vector_type} vectors #{file_name}", %{
  #       file_name: file_name,
  #       vector_type: vector_type
  #     } do
  #       execute_test(file_name, "#{unquote(type)}/#{vector_type}")
  #     end
  #   end
  # end

  describe "encode vectors" do
    for vector_type <- [:tiny, :full] do
      for {file_name, module_name} <- CodecVectors.tests() do
        @tag file_name: file_name
        @tag module_name: module_name
        @tag vector_type: vector_type
        @tag :"#{vector_type}_vectors"
        test "#{vector_type} vector #{file_name} for #{module_name}", %{
          file_name: file_name,
          module_name: module_name,
          vector_type: vector_type
        } do
          assert_correctly_encoded(file_name, module_name, vector_type)
        end
      end
    end
  end

  def assert_correctly_encoded(file_name, module, vector_type) do
    {:ok, json_data} =
      fetch_and_parse_json("#{file_name}.json", "codec/#{vector_type}", @owner, @repo, @branch)

    expected = fetch_binary("#{file_name}.bin", "codec/#{vector_type}", @owner, @repo, @branch)

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
