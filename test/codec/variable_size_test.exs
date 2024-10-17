defmodule Codec.VariableSizeTest do
  use ExUnit.Case

  alias Codec.{Encoder, VariableSize}

  test "encode variable size" do
    assert Encoder.encode(VariableSize.new(nil)) == <<0>>
    assert Encoder.encode(VariableSize.new([])) == <<0>>
    assert Encoder.encode(VariableSize.new(<<>>)) == <<0>>
    assert Encoder.encode(VariableSize.new({})) == <<0>>
    assert Encoder.encode(VariableSize.new(%{})) == <<0>>
    assert Encoder.encode(VariableSize.new([1, 2])) == <<2, 1, 2>>
    assert Encoder.encode(VariableSize.new(<<1, 2, 3>>)) == <<3, 1, 2, 3>>
    assert Encoder.encode(VariableSize.new({1, 2, 3, 4})) == <<4, 1, 2, 3, 4>>
  end

  test "decode" do
    assert VariableSize.decode(<<0>>, :binary) == {<<>>, <<>>}
    assert VariableSize.decode(<<0, 1, 2, 3>>, :binary) == {<<>>, <<1, 2, 3>>}
    assert VariableSize.decode(<<1, 1>>, :binary) == {<<1>>, <<>>}
    assert VariableSize.decode(<<1, 1, 2>>, :binary) == {<<1>>, <<2>>}
    assert VariableSize.decode(<<2, 1, 2>>, :binary) == {<<1, 2>>, <<>>}
    assert VariableSize.decode(<<2, 1, 2, 3>>, :binary) == {<<1, 2>>, <<3>>}
  end
end
