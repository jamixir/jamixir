defmodule Util.MerklizationTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Util.{Hash, Merklization}
  use Sizes

  # Formula (D.3) v0.7.2
  describe "encode_branch/2 (l,r)" do
    test "encode_branch with simple values" do
      # 256-bit value with only the first bit set
      l = Hash.one()
      # 256-bit value with only the second bit set
      r = Hash.two()

      result = Merklization.encode_branch(l, r)

      assert bit_size(result) == Sizes.merkle_root_bits()
      <<b::1, _::bitstring>> = result
      assert b == 0
    end

    test "encode_branch with random inputs" do
      for _ <- 1..100 do
        l = Hash.random()
        r = Hash.random()

        result = Merklization.encode_branch(l, r)

        assert bit_size(result) == Sizes.merkle_root_bits()
        <<b::1, _::bitstring>> = result
        assert b == 0
      end
    end
  end

  # Formula (D.4) v0.7.2

  describe "encode_leaf/2" do
    test "encode_leaf when byte_size(value) < 32 (Embebed)" do
      key = :crypto.strong_rand_bytes(31)

      value = :crypto.strong_rand_bytes(16)

      result = Merklization.encode_leaf(key, value)

      assert bit_size(result) == Sizes.merkle_root_bits()

      <<p1::bitstring-size(2), p2::bitstring-size(6), _::bitstring>> = result
      assert p1 == <<0b10::size(2)>>
      assert p2 == <<0b010000::size(6)>>
    end

    test "encode_leaf when byte_size(value) == 32" do
      key = :crypto.strong_rand_bytes(31)
      result = Merklization.encode_leaf(key, Hash.random())

      assert bit_size(result) == Sizes.merkle_root_bits()
      <<bits::bitstring-size(2), _::bitstring>> = result
      assert bits == <<0b10::2>>
    end

    test "encode_leaf when byte_size(value) > 32" do
      key = :crypto.strong_rand_bytes(31)
      value = :crypto.strong_rand_bytes(33)

      result = Merklization.encode_leaf(key, value)

      assert bit_size(result) == Sizes.merkle_root_bits()
      <<bits::bitstring-size(8), _::bitstring>> = result

      assert bits == <<0b11000000>>
    end
  end

  # Formula (D.5) v0.7.2
  # Formula (D.6) v0.7.2
  describe "meklelize_state/1" do
    test "test big fake state" do
      dict =
        Enum.reduce(1..100, %{}, fn _, acc ->
          <<key::binary-size(31), _::binary>> = Hash.random()
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
