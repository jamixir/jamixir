defmodule NilDiscriminatorTest do
  use ExUnit.Case

  alias Block.Extrinsic.Assurance
  alias Codec.{Encoder, NilDiscriminator}
  import Jamixir.Factory

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

  test "decode nil object" do
    object = NilDiscriminator.new(nil)
    encoded = Encodable.encode(object)
    {decoded, rest} = NilDiscriminator.decode(encoded <> <<1, 2, 3>>, & &1)
    assert decoded == nil
    assert rest == <<1, 2, 3>>
  end

  test "decode binary object" do
    object = NilDiscriminator.new(<<1, 2, 3>>)
    encoded = Encodable.encode(object)

    {decoded, rest} =
      NilDiscriminator.decode(encoded <> <<4, 5, 6>>, fn b ->
        <<x::binary-size(3), rest::binary>> = b
        {x, rest}
      end)

    assert decoded == <<1, 2, 3>>
    assert rest == <<4, 5, 6>>
  end

  test "decode a real object" do
    assurance = build(:assurance)
    object = NilDiscriminator.new(assurance)
    encoded = Encodable.encode(object)

    {decoded, rest} = NilDiscriminator.decode(encoded <> <<4, 5, 6>>, &Assurance.decode/1)

    assert decoded == assurance
    assert rest == <<4, 5, 6>>
  end
end
