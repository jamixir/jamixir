defmodule ScaleNativeTest do
  use ExUnit.Case
  # alias Codec.Encoder
  alias ScaleNative

  @tag :skip
  test "encode and decode small values" do
    for value <- 0..0x3F do
      encoded = ScaleNative.encode_integer(value)
      decoded = ScaleNative.decode_integer(encoded)
      assert decoded == value
    end
  end
end
