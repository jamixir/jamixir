defmodule Codec.VariableSizeTest do
  use ExUnit.Case
  alias Util.Hash
  alias Block.Extrinsic.Disputes.Culprit
  use Codec.Encoder
  use Sizes
  import Jamixir.Factory
  alias Codec.{Encoder, VariableSize}

  test "encode variable size" do
    assert Encoder.encode(vs(nil)) == <<0>>
    assert Encoder.encode(vs([])) == <<0>>
    assert Encoder.encode(vs(<<>>)) == <<0>>
    assert Encoder.encode(vs({})) == <<0>>
    assert Encoder.encode(%{}) == <<0>>
    assert Encoder.encode(vs([1, 2])) == <<2, 1, 2>>
    assert Encoder.encode(vs(<<1, 2, 3>>)) == <<3, 1, 2, 3>>
    assert Encoder.encode(vs({1, 2, 3, 4})) == <<4, 1, 2, 3, 4>>
  end

  test "decode" do
    assert VariableSize.decode(<<0>>, :binary) == {<<>>, <<>>}
    assert VariableSize.decode(<<0, 1, 2, 3>>, :binary) == {<<>>, <<1, 2, 3>>}
    assert VariableSize.decode(<<1, 1>>, :binary) == {<<1>>, <<>>}
    assert VariableSize.decode(<<1, 1, 2>>, :binary) == {<<1>>, <<2>>}
    assert VariableSize.decode(<<2, 1, 2>>, :binary) == {<<1, 2>>, <<>>}
    assert VariableSize.decode(<<2, 1, 2, 3>>, :binary) == {<<1, 2>>, <<3>>}
  end

  describe "decode big sizes" do
    test "encode with big size" do
      bin1 = <<9::1000*8>>
      {result, _} = VariableSize.decode(Encoder.encode(vs(bin1)), :binary)
      assert result == bin1
    end

    test "decode many objects" do
      items = build_list(300, :culprit)
      encoded = e(vs(items))
      {result, _} = VariableSize.decode(encoded, Culprit)
      assert result == items
    end

    test "decode many hashes" do
      items = for _ <- 1..300, do: Hash.four()
      encoded = e(vs(items))
      {result, _} = VariableSize.decode(encoded, :hash)
      assert result == items
    end

    test "decode mapset" do
      items = for _ <- 1..300, do: Hash.four()
      encoded = e(vs(MapSet.new(items)))
      {result, _} = VariableSize.decode(encoded, :mapset, @hash_size)
      assert result == MapSet.new(items)
    end

    test "decode big map" do
      items = for _ <- 0..300, do: {Hash.random(), Hash.four()}, into: %{}
      {result, _} = VariableSize.decode(e(items), :map, @hash_size, @hash_size)
      assert result == items
    end

    test "decode big list of tuples" do
      items = for _ <- 0..300, do: {Hash.random(), Hash.four()}
      {result, _} = VariableSize.decode(e(vs(items)), :list_of_tuples, @hash_size, @hash_size)
      assert result == items
    end
  end
end
