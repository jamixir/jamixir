defmodule Codec.NilDiscriminator do
  defstruct [:value]

  def new(value) do
    %__MODULE__{value: value}
  end

  defimpl Encodable do
    alias Codec.Encoder

    # Formula (C.9) v0.6.6
    def encode(%Codec.NilDiscriminator{value: value}) do
      case value do
        nil -> <<0>>
        _ -> <<1>> <> Encoder.encode(value)
      end
    end
  end

  import Codec.Encoder

  def decode(bin, :hash) do
    decode(bin, fn <<p::b(hash), r::binary>> -> {p, r} end)
  end

  def decode(bin, callback) do
    <<first::8, rest::binary>> = bin

    case first do
      0 -> {nil, rest}
      1 -> callback.(rest)
    end
  end
end
