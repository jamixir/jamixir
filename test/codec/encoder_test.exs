defmodule CodecEncoderTest do
  use ExUnit.Case
  import Bitwise

  alias Codec.Encoder

  test "encode integers from 0 to 127" do
    assert Encoder.encode(0) == <<0>>
    assert Encoder.encode(63) == <<63>>
    assert Encoder.encode(127) == <<127>>
  end

  test "encode integers from 2^7 to 2^14 (not inclusive)" do
    assert Encoder.encode(1 <<< 7) == <<128, 128>>
    assert Encoder.encode((1 <<< 7) + 1) == <<128, 129>>
    assert Encoder.encode(1 <<< 8) == <<129, 0>>
    assert Encoder.encode((1 <<< 8) + 1) == <<129, 1>>
    assert Encoder.encode((1 <<< 14) - 1) == <<191, 255>>
  end

  test "encode integers from 2^14 to 2^21 (not inclusive)" do
    assert Encoder.encode(1 <<< 14) == <<192, 0, 64>>
    assert Encoder.encode((1 <<< 14) + 1) == <<192, 1, 64>>
    assert Encoder.encode((1 <<< 16) - 1) == <<192, 255, 255>>
    assert Encoder.encode(1 <<< 16) == <<193, 0, 0>>
    assert Encoder.encode((1 <<< 21) - 1) == <<223, 255, 255>>
  end

  test "encode integers from 2^21 to 2^28 (not inclusive)" do
    assert Encoder.encode(1 <<< 21) == <<224, 0, 0, 32>>
    assert Encoder.encode((1 <<< 21) + 1) == <<224, 1, 0, 32>>
    assert Encoder.encode(1 <<< 24) == <<225, 0, 0, 0>>
    assert Encoder.encode((1 <<< 24) + 1) == <<225, 1, 0, 0>>
    assert Encoder.encode((1 <<< 28) - 1) == <<239, 255, 255, 255>>
  end

  test "encode integers from 2^28 to 2^64 (not inclusive)" do
    assert Encoder.encode(1 <<< 28) == <<255, 0, 0, 0, 16, 0, 0, 0, 0>>
    assert Encoder.encode((1 <<< 28) + 1) == <<255, 1, 0, 0, 16, 0, 0, 0, 0>>
    assert Encoder.encode((1 <<< 29) - 1) == <<255, 255, 255, 255, 31, 0, 0, 0, 0>>
    assert Encoder.encode(1 <<< 29) == <<255, 0, 0, 0, 32, 0, 0, 0, 0>>
    assert Encoder.encode((1 <<< 29) + 1) == <<255, 1, 0, 0, 32, 0, 0, 0, 0>>
    assert Encoder.encode(1 <<< 30) == <<255, 0, 0, 0, 64, 0, 0, 0, 0>>
    assert Encoder.encode(1 <<< 31) == <<255, 0, 0, 0, 128, 0, 0, 0, 0>>
    assert Encoder.encode((1 <<< 64) - 1) == <<255, 255, 255, 255, 255, 255, 255, 255, 255>>
  end




  test "encode nil" do
    assert Encoder.encode(nil) == <<0>>
  end

  test "encode string binary" do
    binary = "hello"
    assert Encoder.encode(binary) == binary
  end

  test "encode binary data" do
    binary_data = <<1, 2, 3, 4, 5>>
    assert Encoder.encode(binary_data) == binary_data
  end


  test "encode tuple" do
    assert Encoder.encode({1, 2, 3}) == <<3,1, 2, 3>>
    assert Encoder.encode({256, 256}) == <<2, 129,0, 129, 0>>

  end

  test "encode bit list" do
    assert Encoder.encode([0, 1, 0, 1, 1, 0, 1, 0]) == <<90>>
    assert Encoder.encode([1, 1, 1, 1, 1, 1, 1, 1]) == <<255>>
    assert Encoder.encode([1, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1]) == <<81, 43>>
    assert Encoder.encode([]) == <<>>
  end

end
