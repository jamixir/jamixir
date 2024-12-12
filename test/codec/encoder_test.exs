defmodule CodecEncoderTest do
  use ExUnit.Case

  alias Util.Hash
  alias Codec.Encoder

  describe "encode_integer/1" do
    test "encode integer 0" do
      assert Encoder.encode(0) == <<0>>
    end

    test "encode integer < 2^64" do
      assert Encoder.encode(2 ** 2) == <<4>>
      assert Encoder.encode(2 ** 8) == <<129, 0>>
      assert Encoder.encode(2 ** 8 + 1) == <<129, 1>>
      assert Encoder.encode(2 ** 16) == <<193, 0, 0>>
      assert Encoder.encode(2 ** 64 - 1) == <<255, 255, 255, 255, 255, 255, 255, 255, 255>>
    end

    test "encode integer >= 2^64" do
      assert_raise ArgumentError, fn -> Encoder.encode(2 ** 64) end
    end
  end

  describe "encode/1" do
    test "encode empty sequence" do
      assert Encoder.encode([]) == <<>>
      assert Encoder.encode(<<>>) == <<>>
    end

    test "encode binary data" do
      binary_data = <<1, 2, 3, 4, 5>>
      assert Encoder.encode(binary_data) == binary_data
    end

    test "encode tuple" do
      assert Encoder.encode({1, 2, 3}) == <<1, 2, 3>>
    end

    test "encode tuple with big integers" do
      left = Encoder.encode({2 ** 16, 2 ** 8})
      right = Encoder.encode(2 ** 16) <> Encoder.encode(2 ** 8)
      assert left == right
    end

    test "encode list" do
      assert Encoder.encode([1, 2, 3]) == <<1, 2, 3>>
    end

    test "encode random integer list" do
      random_list = for(_ <- 1..20, do: :rand.uniform(100))
      expected = Enum.reduce(random_list, <<>>, fn x, acc -> acc <> Encoder.encode(x) end)
      assert Encoder.encode(random_list) == expected
    end

    test "encode nil" do
      assert Encoder.encode(nil) == <<>>
    end

    test "encode string binary" do
      binary = "hello"
      assert Encoder.encode(binary) == binary
    end

    test "encode bit list" do
      # trivial case
      assert Encoder.encode([0]) == <<0>>
      assert Encoder.encode([1]) == <<1>>
      # empty list
      assert Encoder.encode([]) == <<>>
      # less than 8 bits long
      # 101 -> 1*2^0 + 0*2^1 + 1*2^2 = 5
      assert Encoder.encode([1, 0, 1]) == <<5>>
      assert Encoder.encode([0, 1, 0, 1, 1]) == <<26>>
      # exactly 8 bits long
      # 1 + 4 + 16 + 64
      assert Encoder.encode([1, 0, 1, 0, 1, 0, 1, 0]) == <<85>>
      # 11111111 -> 255
      assert Encoder.encode([1, 1, 1, 1, 1, 1, 1, 1]) == <<255>>
      # longer than 8 bits but not a multiple of 8
      assert Encoder.encode([1, 0, 1, 0, 1, 0, 1, 0, 1, 1]) == <<85, 3>>
      # longer than 8 bits and a multiple of 8
      assert Encoder.encode([0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]) == <<84, 85>>
    end
  end

  # Formula (301) v0.4.5
  describe "encode_le/2" do
    test "base case when l = 0" do
      assert Encoder.encode_le(0, 0) == <<>>
      assert Encoder.encode_le(555, 0) == <<>>
    end

    test "case when l > 0" do
      assert Encoder.encode_le(0, 1) == <<0>>
      assert Encoder.encode_le(1, 1) == <<1>>
      assert Encoder.encode_le(255, 1) == <<255>>
      assert Encoder.encode_le(256, 1) == <<0>>
      assert Encoder.encode_le(257, 1) == <<1>>
      assert Encoder.encode_le(257, 2) == <<1, 1>>
      assert Encoder.encode_le(65_535, 2) == <<255, 255>>
    end
  end

  describe "encode_mmr/1" do
    test "encode mmr cases" do
      assert Encoder.encode_mmr([]) == <<0>>
      assert Encoder.encode_mmr([2]) == <<1, 1, 2>>
      assert Encoder.encode_mmr([2, 3]) == <<2, 1, 2, 1, 3>>
      assert Encoder.encode_mmr([nil, 3]) == <<2, 0, 1, 3>>
      assert Encoder.encode_mmr([nil, nil]) == <<2, 0, 0>>
    end
  end

  describe "super_peak_mmr/1" do
    setup do
      h1 = Hash.random()
      {:ok, h1: h1}
    end

    test "empty array" do
      assert Encoder.super_peak_mmr([]) == <<0::256>>
      assert Encoder.super_peak_mmr([nil]) == <<0::256>>
      assert Encoder.super_peak_mmr([nil, nil, nil]) == <<0::256>>
    end

    test "one element", %{h1: h1} do
      assert Encoder.super_peak_mmr([h1]) == h1
      assert Encoder.super_peak_mmr([nil, nil, h1]) == h1
      assert Encoder.super_peak_mmr([nil, h1, nil]) == h1
    end

    test "two elements", %{h1: h1} do
      h2 = Hash.random()
      assert Encoder.super_peak_mmr([h1, h2]) == Hash.keccak_256("node" <> h1 <> h2)
    end

    test "three elements", %{h1: h1} do
      h2 = Hash.random()
      h3 = Hash.random()

      assert Encoder.super_peak_mmr([h1, h2, h3]) ==
               Hash.keccak_256(
                 "node" <>
                   Encoder.super_peak_mmr([h1, h2]) <> h3
               )
    end
  end
end
