defmodule UtilsTest do
  use ExUnit.Case

  describe "invert bits" do
    test "inverts bits correctly" do
      binary_value = <<0b10101010, 0b11001100>>
      assert Utils.invert_bits(binary_value) == <<0b01010101, 0b00110011>>
    end
  end

  describe "from_json/1" do
    test "converts hex string to binary" do
      assert JsonDecoder.from_json("0x48656c6c6f") == "Hello"
    end

    test "returns original value if not a valid hex string" do
      assert JsonDecoder.from_json("Hello") == "Hello"
    end

    test "converts hex strings in a list to binaries" do
      assert JsonDecoder.from_json(["0x48656c6c6f", "0x776f726c64"]) == ["Hello", "world"]
    end

    test "converts hex strings in a map to binaries" do
      input = %{"greeting" => "0x48656c6c6f", "target" => "0x776f726c64"}
      expected = %{"greeting" => "Hello", "target" => "world"}
      assert JsonDecoder.from_json(input) == expected
    end

    test "handles nested lists and maps" do
      input = %{
        "greetings" => ["0x48656c6c6f", "0x776f726c64"],
        "nested" => %{"key" => "0x74657374"}
      }

      expected = %{
        "greetings" => ["Hello", "world"],
        "nested" => %{"key" => "test"}
      }

      assert JsonDecoder.from_json(input) == expected
    end

    test "returns original value if not a map, list, or hex string" do
      assert JsonDecoder.from_json(123) == 123
      assert JsonDecoder.from_json(:atom) == :atom
    end
  end

  describe "get_bit/2" do
    test "returns correct bit for a single byte" do
      byte = <<0b10101010>>
      assert Utils.get_bit(byte, 0) == 1
      assert Utils.get_bit(byte, 1) == 0
      assert Utils.get_bit(byte, 2) == 1
      assert Utils.get_bit(byte, 3) == 0
      assert Utils.get_bit(byte, 4) == 1
      assert Utils.get_bit(byte, 5) == 0
      assert Utils.get_bit(byte, 6) == 1
      assert Utils.get_bit(byte, 7) == 0
    end

    test "returns correct bit for multiple bytes" do
      bytes = <<0b10101010, 0b11110000>>
      assert Utils.get_bit(bytes, 7) == 0
      assert Utils.get_bit(bytes, 8) == 1
      assert Utils.get_bit(bytes, 9) == 1
      assert Utils.get_bit(bytes, 15) == 0
    end

    test "works with larger bitstrings" do
      large_bitstring = :crypto.strong_rand_bytes(100)
      # 100 bytes * 8 bits - 1
      bit_index = :rand.uniform(799)
      result = Utils.get_bit(large_bitstring, bit_index)
      assert result in [0, 1]
    end

    test "returns 0 for bits beyond the bitstring length" do
      byte = <<0b11111111>>
      assert Utils.get_bit(byte, 8) == 0
      assert Utils.get_bit(byte, 100) == 0
    end

    test "works with non-byte-aligned bitstrings" do
      bitstring = <<0b1010::4>>
      assert Utils.get_bit(bitstring, 0) == 1
      assert Utils.get_bit(bitstring, 1) == 0
      assert Utils.get_bit(bitstring, 2) == 1
      assert Utils.get_bit(bitstring, 3) == 0
    end
  end

  describe "pad_binary_right/2" do
    test "pads binary with zeros" do
      assert Utils.pad_binary_right(<<1, 2, 3>>, 8) == <<1, 2, 3, 0, 0, 0, 0, 0>>
      assert Utils.pad_binary_right(<<>>, 8) == <<>>

      # test case to match P_W_E(b) (https://github.com/jam-duna/jamtestnet/issues/139
      assert Utils.pad_binary_right(
               <<0x1421199ADDAC7C87873A::80>>,
               Constants.erasure_coded_piece_size()
             ) == <<0x1421199ADDAC7C87873A0000::96>>
    end
  end

  describe "pad_binary/2" do
    test "pads binary with zeros" do
      assert Utils.pad_binary(<<1, 2, 3>>, 8) == <<0, 0, 0, 0, 0, 1, 2, 3>>
      assert Utils.pad_binary(<<>>, 8) == <<0, 0, 0, 0, 0, 0, 0, 0>>
      assert Utils.pad_binary(<<1, 2, 3>>, 1) == <<1, 2, 3>>
    end
  end

  describe "transpose/1" do
    test "transposes empty list" do
      assert Utils.transpose([]) == []
    end

    test "transposes list" do
      assert Utils.transpose([[1, 2, 3], [4, 5, 6], [7, 8, 9]]) == [
               [1, 4, 7],
               [2, 5, 8],
               [3, 6, 9]
             ]
    end

    test "transposes list 1 element" do
      assert Utils.transpose([[1]]) == [[1]]
      assert Utils.transpose([[1, 2, 3]]) == [[1], [2], [3]]
    end

    test "transposes a list of binaries" do
      assert Utils.transpose([<<1, 2, 3>>, <<4, 5, 6>>, <<7, 8, 9>>]) == [
               <<1, 4, 7>>,
               <<2, 5, 8>>,
               <<3, 6, 9>>
             ]
    end
  end
end
