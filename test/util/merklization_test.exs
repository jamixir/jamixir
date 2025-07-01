defmodule Util.MerklizationTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Util.{Hash, Merklization}
  use Sizes

  # Formula (D.3) v0.7.0
  describe "encode_branch/2 (l,r)" do
    test "encode_branch with simple values" do
      # 256-bit value with only the first bit set
      l = Hash.one()
      # 256-bit value with only the second bit set
      r = Hash.two()

      result = Merklization.encode_branch(l, r)

      assert is_list(result)
      assert length(result) == Sizes.merkle_root_bits()
      [b | _] = result
      assert b == 0
    end

    test "encode_branch with random inputs" do
      for _ <- 1..100 do
        l = Hash.random()
        r = Hash.random()

        result = Merklization.encode_branch(l, r)

        assert is_list(result)
        assert length(result) == Sizes.merkle_root_bits()
        [b | _] = result
        assert b == 0
      end
    end
  end

  # Formula (D.4) v0.7.0

  describe "encode_leaf/2" do
    test "encode_leaf when byte_size(value) < 32 (Embebed)" do
      key = :crypto.strong_rand_bytes(31)

      value = :crypto.strong_rand_bytes(16)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == Sizes.merkle_root_bits()

      assert Enum.slice(result, 0, 2) == [1, 0]

      assert Enum.slice(result, 2, 6) == Merklization.bits(<<16>>) |> Enum.drop(2)
    end

    test "encode_leaf when byte_size(value) == 32" do
      key = :crypto.strong_rand_bytes(31)

      result = Merklization.encode_leaf(key, Hash.random())

      assert length(result) == Sizes.merkle_root_bits()

      assert Enum.slice(result, 0, 2) == [1, 0]
    end

    test "encode_leaf when byte_size(value) > 32" do
      key = :crypto.strong_rand_bytes(31)
      value = :crypto.strong_rand_bytes(33)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == Sizes.merkle_root_bits()

      assert Enum.slice(result, 0, 8) == [1, 1, 0, 0, 0, 0, 0, 0]
    end
  end

  describe "bits" do
    test "bits function with single byte" do
      # Binary representation: 00101010
      input = <<42>>
      expected = [0, 0, 1, 0, 1, 0, 1, 0]
      assert Merklization.bits(input) == expected
    end

    test "bits function most significant first" do
      input = <<160, 0>>
      expected = [1, 0, 1] ++ List.duplicate(0, 13)
      assert Merklization.bits(input) == expected
    end

    test "bits for multiple octets(bytes)" do
      octets = <<5, 0, 5>>
      # 505 in binary
      expected_bits = [0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1]

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
      assert Merklization.bits_to_bytes(bits) == <<170>>
    end

    test "bits_to_bytes with multiple bytes" do
      bits = [1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1]
      assert Merklization.bits_to_bytes(bits) == <<170, 85>>
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

  # Formula (D.5) v0.7.0
  # Formula (D.6) v0.7.0
  describe "meklelize_state/1" do
    test "smoke test fake state" do
      dict = %{<<1>> => "a", <<2>> => "b"}

      transformed_dict = %{
        [0, 0, 0, 0, 0, 0, 0, 1] => {<<1>>, "a"},
        [0, 0, 0, 0, 0, 0, 1, 0] => {<<2>>, "b"}
      }

      assert Merklization.merkelize_state(dict) == Merklization.merkelize(transformed_dict)
    end

    test "test big fake state" do
      dict =
        Enum.reduce(1..100, %{}, fn _, acc ->
          key = Hash.random()
          value = Hash.random()
          Map.put(acc, key, value)
        end)

      hash = Merklization.merkelize_state(dict)
      assert is_binary(hash)
      assert byte_size(hash) == @hash_size
    end

    test "smoke test real state" do
      hash = Codec.State.Trie.state_root(build(:genesis_state))
      assert is_binary(hash)
      assert byte_size(hash) == @hash_size
    end
  end
end
