defmodule ScaleEncodingTest do
  use ExUnit.Case
  doctest ScaleEncoding

  test "encode and decode small values" do
    for value <- 0..0x3F do
      encoded = ScaleEncoding.encode_integer(value)
      decoded = ScaleEncoding.decode_integer(encoded)
      assert decoded == value
    end
  end

  test "encode and decode medium values" do
    for value <- 0x40..0x3FFF do
      encoded = ScaleEncoding.encode_integer(value)
      decoded = ScaleEncoding.decode_integer(encoded)
      assert decoded == value
    end
  end

  test "encode and decode large values" do
    values_to_test = [
      0x4000,          # Minimum value
      0x4000 + 1,      # Just above the minimum
      0x3FFFFFFF - 1,  # Just below the maximum
      0x3FFFFFFF,      # Maximum value
      0x20000000,      # A value in the middle
      0x10000000       # Another value in the middle
    ]

    for value <- values_to_test do
      encoded = ScaleEncoding.encode_integer(value)
      decoded = ScaleEncoding.decode_integer(encoded)
      assert decoded == value
    end
  end

  test "encode and decode very large values" do
    values_to_test = [
      0x40000000,          # Minimum value
      0x40000000 + 1,      # Just above the minimum
      0x2000000000000000,       #  value in the middle
      0x4000000000000000 - 1,  # Just below the maximum
    ]

    for value <- values_to_test do
      encoded = ScaleEncoding.encode_integer(value)
      decoded = ScaleEncoding.decode_integer(encoded)
      assert decoded == value
    end
  end
end