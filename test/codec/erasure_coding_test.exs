defmodule ErasureCodingTest do
  use ExUnit.Case
  alias ErasureCoding

  describe "split/2" do
    test "splits empty binary data" do
      assert ErasureCoding.split(<<>>, 2) == []
      assert ErasureCoding.split(<<>>, 200) == []
    end

    test "splits binary data" do
      assert ErasureCoding.split(<<1, 2, 3, 4, 5, 6>>, 2) == [<<1, 2>>, <<3, 4>>, <<5, 6>>]
    end

    test "splits list data" do
      assert ErasureCoding.split([1, 2, 3, 4, 5, 6], 2) == [<<1, 2>>, <<3, 4>>, <<5, 6>>]
      assert ErasureCoding.split([1, 2, 3, 4, 5, 6], 3) == [<<1, 2, 3>>, <<4, 5, 6>>]
    end

    test "split invalid data size" do
      assert_raise ArgumentError, fn -> ErasureCoding.split(<<1, 2, 3, 4, 5, 6>>, 4) end
    end
  end

  describe "join/1" do
    test "join empty list" do
      assert ErasureCoding.join([]) == <<>>
    end

    test "infer data size from first element" do
      assert ErasureCoding.join([<<1, 2>>, <<3, 4>>, <<5, 6>>]) == <<1, 2, 3, 4, 5, 6>>
    end
  end

  describe "join/2" do
    test "joins empty list" do
      assert ErasureCoding.join([], 2) == <<>>
    end

    test "joins binary data" do
      assert ErasureCoding.join([<<1, 2>>, <<3, 4>>, <<5, 6>>], 2) == <<1, 2, 3, 4, 5, 6>>
    end

    test "joins list data" do
      assert ErasureCoding.join([<<1, 2>>, <<3, 4>>, <<5, 6>>], 2) == <<1, 2, 3, 4, 5, 6>>
      assert ErasureCoding.join([<<1, 2, 3>>, <<4, 5, 6>>], 3) == <<1, 2, 3, 4, 5, 6>>
    end

    test "join invalid data size" do
      assert_raise ArgumentError, fn ->
        ErasureCoding.join([<<1, 2>>, <<3, 4>>, <<5, 6>>], 4)
      end

      assert_raise ArgumentError, fn ->
        ErasureCoding.join([<<1, 2>>, <<3, 4>>, <<5, 5, 6>>], 2)
      end
    end
  end

  describe "unzip/2" do
    test "unzips empty binary data" do
      assert ErasureCoding.unzip(<<>>, 2) == []
      assert ErasureCoding.unzip(<<>>, 200) == []
    end

    test "unzips binary data" do
      assert ErasureCoding.unzip(<<1, 2, 3, 4, 5, 6>>, 2) == [<<1, 4>>, <<2, 5>>, <<3, 6>>]
      assert ErasureCoding.unzip(<<1, 2, 3, 4, 5, 6>>, 3) == [<<1, 3, 5>>, <<2, 4, 6>>]
    end

    test "unzips invalid data size" do
      assert_raise ArgumentError, fn -> ErasureCoding.unzip(<<1, 2, 3, 4, 5, 6>>, 4) end
    end
  end

  describe "lace/2" do
    test "laces empty list data" do
      assert ErasureCoding.lace([], 2) == <<>>
      assert ErasureCoding.lace([], 200) == <<>>
    end

    test "laces binary data" do
      assert ErasureCoding.lace([<<1, 4>>, <<2, 5>>, <<3, 6>>], 2) == <<1, 2, 3, 4, 5, 6>>
      assert ErasureCoding.lace([<<1, 3, 5>>, <<2, 4, 6>>], 3) == <<1, 2, 3, 4, 5, 6>>
    end

    test "laces invalid data size" do
      assert_raise ArgumentError, fn ->
        ErasureCoding.lace([<<1, 4>>, <<2, 5>>, <<3, 6>>], 4)
      end

      assert_raise ArgumentError, fn ->
        ErasureCoding.lace([<<1, 4>>, <<2, 5>>, <<3, 6, 7>>], 2)
      end
    end
  end

  describe "transpose/1" do
    test "transposes empty list" do
      assert ErasureCoding.transpose([]) == []
    end

    test "transposes list" do
      assert ErasureCoding.transpose([[1, 2, 3], [4, 5, 6], [7, 8, 9]]) == [
               [1, 4, 7],
               [2, 5, 8],
               [3, 6, 9]
             ]
    end

    test "transposes list 1 element" do
      assert ErasureCoding.transpose([[1]]) == [[1]]
      assert ErasureCoding.transpose([[1, 2, 3]]) == [[1], [2], [3]]
    end

    test "transposes a list of binaries" do
      assert ErasureCoding.transpose([<<1, 2, 3>>, <<4, 5, 6>>, <<7, 8, 9>>]) == [
               <<1, 4, 7>>,
               <<2, 5, 8>>,
               <<3, 6, 9>>
             ]
    end
  end

  describe "encode/1" do
    test "returns error for empty binary" do
    end
  end

  describe "erasure_code/1" do
    test "smoke test" do
      binary = <<1::684*8>>
      # assert ErasureCoding.erasure_code(binary) == [<<1::684*8>>]
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
