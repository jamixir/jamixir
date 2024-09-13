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
end
