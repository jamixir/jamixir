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

  describe "encode smoke/1" do
    test "smoke test" do
      binary =
        Base.decode16!(
          "9c077029c120e6de118edc7bfdd79ed4834115dbfa9ed309aa2339053bb3a07a313e536e8538c962b571fa57c15572ae44fb0f766b16b8e6a7c44ab69caa955c9ab37c217d963dd9d8e4b708348c899a8766a899434dfeacf18fe8d947477e0bc954537d9ad80cd9241205930531432c5c623a9c77ae0865c62b057ab1553331811fe0561f49fc69a6453b799914a0974e114f4e40775af050e723c7d20d0ba6f1ad6524b7a11ac3680da41d1c580cde055a2a1d70fabeaebe14699038b2db6ac4a0d362eeccd36bce908b62c8decfa9ef57f7514e25119288f81581bc15da084f1d977c0e7c3db6c976f6b2a11eb370dcaf4c4fc9fbd884eab541b3970144013ecaa56ae56580cdba4c87aac4e9aec4e6b293cac13ea48ba10c3bdc7408834a16b9f4f888aef5820e8f96e41bfd7e872f33e2773d43ebef7d3c45dc4d869fc6437012b01d14093dd21c18694896dbf295199f76a3a2ca2c3aa4fef98b3e35559bfc43924645bf9c5fd532a8d8466ab0f47c1ecfade8d90cdb3632d935ca96e4c97e51afb2b2dd92745c4b17e9e5efb3bbd1b9819faa980e18b4d5d0e2660d95d493cefeb158f8611ebde40b17df55981ea1fb24d9da7ea6cd2ee31583f1190df11547e7fe5159e0d25b4c1442baa331002f376e90548691b90c25f9a805d3391586e599d1d18aa0e12a0a2436bfcf4d936129bf6d083ec11a9d91419071aa9685e1cd99dbb9626d4031da55b5c6ed4f45722a06f9568d7a516fee5524bc4f86869f0f35cf5a2f499480aa62efa02ee377c0d286addce565e3c3e51d149a5818a59f94a14cb762b5e1882049c4ceb9ef38923b5702e871c6bfa9c7fe6d1c1cc2439078b5d816c6914f15d41cd60df4ba9dfa0b8ce68978fe681731c2c6a8caeff417137a4b1c59142060e29f59665c1550f6ee292c395bc08eb144a5d2383893a4cb3abf34f38e8396e8a574",
          case: :lower
        )

      result = ErasureCoding.encode_bin(binary)
      assert length(result) == 1023
    end
  end

  # describe "ck/1" do
  #   @tag :skip
  #   test "correctly encodes data" do
  #     # Read and parse the JSON file
  #     {:ok, json} = File.read(Path.expand("./test_vectors.json", __DIR__))

  #     %{"data" => data, "segment" => %{"segments" => [%{"segment_ec" => expected_segments}]}} =
  #       Jason.decode!(json)

  #     # Convert the data from hex string to binary
  #     data_binary = Base.decode16!(data, case: :mixed)

  #     # Convert the expected segments from hex strings to binaries
  #     expected_binaries = Enum.map(expected_segments, &Base.decode16!(&1, case: :mixed))

  #     # Call the ck function
  #     result = ErasureCoding.encode_native(684, data_binary)

  #     # Assert the result matches the expected segments
  #     assert result == expected_binaries
  #   end
  # end
end
