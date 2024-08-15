defmodule NilDiscriminatorTest do
  use ExUnit.Case

  alias Codec.{Encoder, NilDiscriminator}

  test "encode nil discriminator" do
    assert Encoder.encode(NilDiscriminator.new(nil)) == <<0>>
    assert Encoder.encode(NilDiscriminator.new(0)) == <<1, 0>>
    assert Encoder.encode(NilDiscriminator.new(1)) == <<1, 1>>
    assert Encoder.encode(NilDiscriminator.new(<<1>>)) == <<1, 1>>
    assert Encoder.encode(NilDiscriminator.new(<<>>)) == <<1>>
    assert Encoder.encode(NilDiscriminator.new({1})) == <<1, 1>>
    assert Encoder.encode(NilDiscriminator.new({})) == <<1>>
    assert Encoder.encode(NilDiscriminator.new([1])) == <<1, 1>>
    assert Encoder.encode(NilDiscriminator.new([])) == <<1>>
  end
end
