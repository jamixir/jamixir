defmodule Util.MerklizationTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State
  alias Util.Merklization

  # Formula (315) v0.4.1: TESTS

  describe "encode_branch/2 (l,r)" do
    test "encode_branch with simple values" do
      # 256-bit value with only the first bit set
      l = <<1::256>>
      # 256-bit value with only the second bit set
      r = <<2::256>>

      result = Merklization.encode_branch(l, r)

      assert is_list(result)
      assert length(result) == 512
      [b | _] = result
      assert b == 0
    end

    test "encode_branch with random inputs" do
      for _ <- 1..100 do
        l = :crypto.strong_rand_bytes(32)
        r = :crypto.strong_rand_bytes(32)

        result = Merklization.encode_branch(l, r)

        assert is_list(result)
        assert length(result) == 512
        [b | _] = result
        assert b == 0
      end
    end
  end

  # Formula (316) v0.4.1: TESTS

  describe "encode_leaf/2" do
    test "encode_leaf when byte_size(value) < 32 (Embebed)" do
      key = :crypto.strong_rand_bytes(31)

      value = :crypto.strong_rand_bytes(16)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == 512

      assert Enum.slice(result, 0, 2) == [1, 0]

      assert Enum.slice(result, 2, 6) == [0, 0, 0, 0, 1, 0]
    end

    test "encode_leaf when byte_size(value) == 32" do
      key = :crypto.strong_rand_bytes(31)

      value = :crypto.strong_rand_bytes(32)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == 512

      assert Enum.slice(result, 0, 2) == [1, 0]
    end

    test "encode_leaf when byte_size(value) > 32" do
      key = :crypto.strong_rand_bytes(31)
      value = :crypto.strong_rand_bytes(33)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == 512

      assert Enum.slice(result, 0, 8) == [1, 1, 0, 0, 0, 0, 0, 0]
    end
  end

  # Formula (317) v0.4.1: TESTS
  # Formula (318) v0.4.1: TESTS

  ### 3.7.3

  describe "bits" do
    test "bits function with single byte" do
      # Binary representation: 00101010
      input = <<42>>
      expected = [0, 1, 0, 1, 0, 1, 0, 0]
      assert Merklization.bits(input) == expected
    end

    test "bits for multiple octets(bytes)" do
      octets = <<5, 0, 5>>
      # 505 in binary
      expected_bits = [1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0]

      assert Merklization.bits(octets) == expected_bits
    end

    test "bits function with empty binary" do
      input = <<>>
      expected = []
      assert Merklization.bits(input) == expected
    end

    test "bits function with all bits set" do
      # Binary: 11111111 11111111
      input = <<255, 255>>
      expected_bits = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      assert Merklization.bits(input) == expected_bits
    end
  end

  describe "bits_to_bytes/1" do
    test "bits_to_bytes with empty list" do
      assert Merklization.bits_to_bytes([]) == <<>>
    end

    test "bits_to_bytes with single byte" do
      bits = [1, 0, 1, 0, 1, 0, 1, 0]
      assert Merklization.bits_to_bytes(bits) == <<85>>
    end

    test "bits_to_bytes with multiple bytes" do
      bits = [1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1]
      assert Merklization.bits_to_bytes(bits) == <<85, 170>>
    end

    test "bits_to_bytes with partial byte" do
      bits = [1, 0, 1, 0, 1]
      assert Merklization.bits_to_bytes(bits) == <<21>>
    end

    test "bits_to_bytes reversibility" do
      original = :crypto.strong_rand_bytes(10)
      bits = Merklization.bits(original)
      result = Merklization.bits_to_bytes(bits)
      assert result == original
    end
  end

  describe "meklelize_state/1" do
    test "smoke test fake state" do
      dict = %{<<1>> => "a", <<2>> => "b"}

      transformed_dict = %{
        [1, 0, 0, 0, 0, 0, 0, 0] => {<<1>>, "a"},
        [0, 1, 0, 0, 0, 0, 0, 0] => {<<2>>, "b"}
      }

      assert Merklization.merkelize_state(dict) == Merklization.merkelize(transformed_dict)
    end

    test "test big fake state" do
      dict =
        Enum.reduce(1..100, %{}, fn _, acc ->
          key = :crypto.strong_rand_bytes(32)
          value = :crypto.strong_rand_bytes(32)
          Map.put(acc, key, value)
        end)

      hash = Merklization.merkelize_state(dict)
      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "smoke test real state" do
      hash = build(:genesis_state) |> State.serialize() |> Merklization.merkelize_state()
      assert is_binary(hash)
      assert byte_size(hash) == 32
    end
  end
end
