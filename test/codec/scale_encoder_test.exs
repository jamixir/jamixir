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
      # Minimum value
      0x4000,
      # Just above the minimum
      0x4000 + 1,
      # Just below the maximum
      0x3FFFFFFF - 1,
      # Maximum value
      0x3FFFFFFF,
      # A value in the middle
      0x20000000,
      # Another value in the middle
      0x10000000
    ]

    for value <- values_to_test do
      encoded = ScaleEncoding.encode_integer(value)
      decoded = ScaleEncoding.decode_integer(encoded)
      assert decoded == value
    end
  end

  test "encode and decode very large values" do
    values_to_test = [
      # Minimum value
      0x40000000,
      # Just above the minimum
      0x40000000 + 1,
      #  value in the middle
      0x2000000000000000,
      # Just below the maximum
      0x4000000000000000 - 1
    ]

    for value <- values_to_test do
      encoded = ScaleEncoding.encode_integer(value)
      decoded = ScaleEncoding.decode_integer(encoded)
      assert decoded == value
    end
  end
end
