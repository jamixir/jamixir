defmodule Codec.EncodeDecodeTest do
  use ExUnit.Case
  alias Codec.{Encoder, Decoder}

  describe "encode_le/2 and decode_le/2" do
    test "encode and decode returns the original value" do
      value = 0
      length = 1
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 1
      length = 1
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 255
      length = 1
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 256
      length = 2
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 257
      length = 2
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 65535
      length = 2
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 65536
      length = 3
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 16777215
      length = 3
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value

      value = 4294967295
      length = 4
      encoded = Encoder.encode_le(value, length)
      decoded = Decoder.decode_le(encoded, length)
      assert decoded == value
    end
  end
end
