defmodule ScaleNativeTest do
  use ExUnit.Case

  test "encode and decode small values" do
    for value <- 0..0x3F do
      encoded = ScaleNative.encode_compact_integer(value)
      # decoded = ScaleNative.decode_integer(encoded)
      assert encoded == "sss"
    end
  end
end
