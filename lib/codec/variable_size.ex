defmodule Codec.VariableSize do
  defstruct [:value, :size]

  def new(value) do
    %__MODULE__{value: value, size: size(value)}
  end

  defp size(value) when is_list(value), do: length(value)
  defp size(value) when is_tuple(value), do: tuple_size(value)
  defp size(value) when is_binary(value), do: byte_size(value)
  defp size(%MapSet{} = v), do: MapSet.size(v)
  # Default case
  defp size(_value), do: 0

  defimpl Encodable do
    alias Codec.Encoder
    # Formula (297) v0.4.1
    def encode(%Codec.VariableSize{value: value, size: size}) do
      Encoder.encode(size) <> Encoder.encode(value)
    end
  end

  def decode(bin, module) do
    <<count::integer, rest::binary>> = bin

    Enum.reduce(1..count, {[], rest}, fn _, {acc, rest} ->
      {value, rest} = module.decode(rest)
      {acc ++ [value], rest}
    end)
  end
end
