defmodule Codec.VariableSize do
  import RangeMacros
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
    # Formula (303) v0.4.5
    def encode(%Codec.VariableSize{value: value, size: size}) do
      Encoder.encode(size) <> Encoder.encode(value)
    end
  end

  use Sizes

  def decode(bin, :binary) do
    <<size::integer, rest::binary>> = bin
    <<value::binary-size(size), rest::binary>> = rest
    {value, rest}
  end

  def decode(bin, :hash) do
    <<count::integer, rest::binary>> = bin

    Enum.reduce(from_0_to(count), {[], rest}, fn _, {acc, rest} ->
      <<value::binary-size(@hash_size), r::binary>> = rest
      {acc ++ [value], r}
    end)
  end

  def decode(bin, module) do
    <<count::integer, rest::binary>> = bin
    decode(rest, module, count)
  end

  def decode(bin, :mapset, value_size) do
    <<count::integer, rest::binary>> = bin

    Enum.reduce(from_0_to(count), {MapSet.new(), rest}, fn _, {acc, rest} ->
      <<value::binary-size(value_size), r::binary>> = rest
      {MapSet.put(acc, value), r}
    end)
  end

  def decode(bin, module, count) do
    Enum.reduce(from_0_to(count), {[], bin}, fn _, {acc, bin} ->
      {value, r} = module.decode(bin)
      {acc ++ [value], r}
    end)
  end

  def decode(bin, :map, key_size, value_size) do
    <<count::8, rest::binary>> = bin

    Enum.reduce(from_0_to(count), {%{}, rest}, fn _, {acc, rest} ->
      <<key::binary-size(key_size), value::binary-size(value_size), rest::binary>> = rest
      {Map.put(acc, key, value), rest}
    end)
  end
end
