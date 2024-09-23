defmodule UtilsTest do
  use ExUnit.Case

  describe "invert bits" do
    test "inverts bits correctly" do
      binary_value = <<0b10101010, 0b11001100>>
      assert Utils.invert_bits(binary_value) == <<0b01010101, 0b00110011>>
    end
  end

  describe "hex_to_binary/1" do
    test "converts hex string to binary" do
      assert Utils.hex_to_binary("0x48656c6c6f") == "Hello"
    end

    test "returns original value if not a valid hex string" do
      assert Utils.hex_to_binary("Hello") == "Hello"
    end

    test "converts hex strings in a list to binaries" do
      assert Utils.hex_to_binary(["0x48656c6c6f", "0x776f726c64"]) == ["Hello", "world"]
    end

    test "converts hex strings in a map to binaries" do
      input = %{"greeting" => "0x48656c6c6f", "target" => "0x776f726c64"}
      expected = %{"greeting" => "Hello", "target" => "world"}
      assert Utils.hex_to_binary(input) == expected
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

      assert Utils.hex_to_binary(input) == expected
    end

    test "returns original value if not a map, list, or hex string" do
      assert Utils.hex_to_binary(123) == 123
      assert Utils.hex_to_binary(:atom) == :atom
    end
  end
end
