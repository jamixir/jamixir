defmodule Codec.EncodeDecodeTest do
  use ExUnit.Case
  alias Codec.{Decoder, Encoder}

  describe "encode_le/2 and decode_le/2" do
    test "encode and decode returns the original value" do
      test_cases = [
        {0, 1},
        {1, 1},
        {255, 1},
        {256, 2},
        {257, 2},
        {65_535, 2},
        {65_536, 3},
        {16_777_215, 3},
        {4_294_967_295, 4}
      ]

      Enum.each(test_cases, fn {value, size} ->
        encoded = Encoder.encode_le(value, size)
        decoded = Decoder.decode_le(encoded, size)

        assert decoded == value, "Failed for value: #{value}"
      end)
    end
  end

  describe "encode_integer/1 and decode_integer/1" do
    test "encode and decode returns the original value" do
      test_cases = [
        0,
        1,
        255,
        256,
        257,
        65_535,
        65_536,
        16_777_215,
        4_294_967_295,
        4_294_967_296,
        # Just below 2^56
        72_057_594_037_927_935,
        # Exactly 2^56
        72_057_594_037_927_936,
        # Large integer
        1_234_567_890_123_456_789,
        # 2^64 - 1
        18_446_744_073_709_551_615
      ]

      Enum.each(test_cases, fn value ->
        assert Decoder.decode_integer(Encoder.encode(value)) == value,
               "Failed for value: #{value}"
      end)
    end

    test "encode and decode works for random large integers" do
      Enum.each(1..100, fn _ ->
        value = :rand.uniform(1_000_000_000_000_000)

        assert Decoder.decode_integer(Encoder.encode(value)) == value,
               "Failed for random value: #{value}"
      end)
    end
  end
end
