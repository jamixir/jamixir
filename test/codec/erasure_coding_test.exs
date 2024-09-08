defmodule ErasureCodingTest do
  use ExUnit.Case
  alias ErasureCoding

  describe "split/2" do
    test "splits binary data" do
      assert ErasureCoding.split(<<1, 2, 3, 4, 5, 6>>, 2) == [
               <<1, 2>>,
               <<3, 4>>,
               <<5, 6>>
             ]
    end

    test "splits list data" do
      assert ErasureCoding.split([1, 2, 3, 4, 5, 6], 2) == [<<1, 2>>, <<3, 4>>, <<5, 6>>]
    end
  end

  describe "encode/1" do
    test "returns error for empty binary" do
    end
  end

  describe "ck/1" do
    @tag :skip
    test "correctly encodes data" do
      # Read and parse the JSON file
      {:ok, json} = File.read(Path.expand("./test_vectors.json", __DIR__))

      %{"data" => data, "segment" => %{"segments" => [%{"segment_ec" => expected_segments}]}} =
        Jason.decode!(json)

      # Convert the data from hex string to binary
      data_binary = Base.decode16!(data, case: :mixed)

      # Convert the expected segments from hex strings to binaries
      expected_binaries = Enum.map(expected_segments, &Base.decode16!(&1, case: :mixed))

      # Call the ck function
      result = ErasureCoding.encode_native(684, data_binary)

      # Assert the result matches the expected segments
      assert result == expected_binaries
    end
  end
end
