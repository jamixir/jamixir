defmodule Codec.VariableSize do
  import RangeMacros
  import Codec.Decoder
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
    import Codec.Encoder
    # Formula (C.7) v0.7.2
    def encode(%Codec.VariableSize{} = x), do: e(x.size) <> e(x.value)
  end

  use Sizes

  def decode(bin, :binary) do
    {size, rest} = de_i(bin)
    <<value::binary-size(size), rest::binary>> = rest
    {value, rest}
  end

  def decode(bin, :hash) do
    {count, rest} = de_i(bin)

    Enum.reduce(from_0_to(count), {[], rest}, fn _, {acc, rest} ->
      <<value::binary-size(@hash_size), r::binary>> = rest
      {acc ++ [value], r}
    end)
  end

  def decode(bin, :map_int) do
    {count, rest} = de_i(bin)

    Enum.reduce(from_0_to(count), {%{}, rest}, fn _, {acc, rest} ->
      {key, rest} = de_i(rest)
      {value, rest} = de_i(rest)
      {Map.put(acc, key, value), rest}
    end)
  end

  def decode(bin, func) when is_function(func) do
    {count, rest} = de_i(bin)
    decode(rest, func, count)
  end

  def decode(bin, module) do
    decode(bin, &module.decode/1)
  end

  def decode(bin, :mapset, value_size) do
    {count, rest} = de_i(bin)

    Enum.reduce(from_0_to(count), {MapSet.new(), rest}, fn _, {acc, rest} ->
      <<value::binary-size(value_size), r::binary>> = rest
      {MapSet.put(acc, value), r}
    end)
  end

  def decode(bin, func, count) when is_function(func) do
    Enum.reduce(from_0_to(count), {[], bin}, fn _, {acc, bin} ->
      {value, r} = func.(bin)
      {acc ++ [value], r}
    end)
  end

  def decode(bin, module, count) do
    decode(bin, &module.decode/1, count)
  end

  def decode(bin, :map, key_size, value_size) do
    {count, rest} = de_i(bin)

    Enum.reduce(from_0_to(count), {%{}, rest}, fn _, {acc, rest} ->
      <<key::binary-size(key_size), value::binary-size(value_size), rest::binary>> = rest
      {Map.put(acc, key, value), rest}
    end)
  end

  def decode(bin, :list_of_tuples, size0, size1) do
    {count, rest} = de_i(bin)

    Enum.reduce(from_0_to(count), {[], rest}, fn _, {acc, rest} ->
      <<key::binary-size(size0), value::binary-size(size1), rest::binary>> = rest
      {acc ++ [{key, value}], rest}
    end)
  end
end
