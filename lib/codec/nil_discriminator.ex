defmodule Codec.NilDiscriminator do
  defstruct [:value]

  def new(value) do
    %__MODULE__{value: value}
  end

  defimpl Encodable do
    alias Codec.Encoder

    def encode(%Codec.NilDiscriminator{value: value}) do
      case value do
        nil -> <<0>>
        _ -> <<1>> <> Encoder.encode(value)
      end
    end
  end
end
