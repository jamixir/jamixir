defmodule Codec.VariableSizeTest do
  use ExUnit.Case

  alias Codec.{Encoder, VariableSize}

  test "encode variable size" do
    assert Encoder.encode(VariableSize.new([])) == <<0>>
    assert Encoder.encode(VariableSize.new(<<>>)) == <<0>>
    assert Encoder.encode(VariableSize.new({})) == <<0>>
    assert Encoder.encode(VariableSize.new([1, 2])) == <<2, 1, 2>>
    assert Encoder.encode(VariableSize.new(<<1, 2, 3>>)) == <<3, 1, 2, 3>>
    assert Encoder.encode(VariableSize.new({1, 2, 3, 4})) == <<4, 1, 2, 3, 4>>
  end

end
