defmodule Codec.NilDiscriminator do
  defstruct [:value]

  def new(value) do
    %__MODULE__{value: value}
  end

  defimpl Encodable do
    alias Codec.Encoder

    # Formula (298) v0.4.1
    def encode(%Codec.NilDiscriminator{value: value}) do
      case value do
        nil -> <<0>>
        _ -> <<1>> <> Encoder.encode(value)
      end
    end
  end
end
