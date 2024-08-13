defmodule Codec.Encoder do
  @moduledoc """
  A module for encoding data structures into binary format.
  """
  alias Codec.VariableSize

  @doc """
  Encodes a given value into a binary format.
  """
  @spec encode(any()) :: binary()
  def encode(value) do
    do_encode(value)
  end

  # Formula (271) v0.3.4
  @spec encode_little_endian(integer(), integer()) :: binary()
  def encode_little_endian(_, 0), do: <<>>

  def encode_little_endian(x, l) do
    <<rem(x, 256)>> <> encode_little_endian(div(x, 256), l - 1)
  end

  @spec encode_le(integer(), integer()) :: binary()
  def encode_le(x, l), do: encode_little_endian(x, l)

  # Private Functions

  defp is_bit_list([]), do: true
  defp is_bit_list([0 | rest]), do: is_bit_list(rest)
  defp is_bit_list([1 | rest]), do: is_bit_list(rest)
  defp is_bit_list(_), do: false

  # Formula (269) v0.3.4
  defp do_encode(nil), do: <<>>
  # Formula (270) v0.3.4
  defp do_encode(value) when is_binary(value), do: value
  # Formula (271) v0.3.4
  defp do_encode(value) when is_tuple(value), do: value |> Tuple.to_list() |> encode_list()
  # Formula (272) is not implementable in Elixir,
  # as it does not have a built-in arbitrary number of arguments in functions

  # Formula (276) v0.3.4
  defp do_encode(value) when is_list(value) do
    if is_bit_list(value) do
      encode_bits(value)
    else
      encode_list(value)
    end
  end

  # Formula (277) v0.3.4
  defp do_encode(%VariableSize{value: value, size: size}) do
    do_encode(size) <> do_encode(value)
  end

  defp do_encode(value) when is_struct(value) do
    if encodable?(value) do
      Encodable.encode(value)
    else
      raise "Struct does not implement Encodable protocol"
    end
  end

  # Formula (278) - no longer part of GP in v0.3.4
  defp do_encode(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.map(fn {key, value} -> {do_encode(key), do_encode(value)} end)
    |> VariableSize.new()
    |> do_encode
  end

  defp do_encode(value) when is_integer(value), do: encode_integer(value)
  defp do_encode(value) when is_list(value), do: encode_list(value)

  defp do_encode(%_{} = struct) do
    # Delegate to Encodable protocol for structs
    Encodable.encode(struct)
  end

  defp encodable?(data) do
    not is_nil(Encodable.impl_for(data))
  end

  # defp do_encode(%Block.Header{} = header), do: encode_header(header)

  # l = 0 => 2 < x < 2^7
  # l = 1 => 2^7 <= x < 2^14
  # l = 2 => 2^14 <= x < 2^21
  # ...
  # l = 7 => 2^49 <= x < 2^56
  # Formula (275) v0.3.4
  defp exists_l_in_N8(x) do
    l = trunc(:math.log2(x) / 7)

    if l in 0..7 do
      l
    else
      nil
    end
  end

  # Formula (275) v0.3.4
  defp encode_integer(0), do: <<0>>

  # Formula (275) v0.3.4
  defp encode_integer(x) do
    if x >= 2 ** 64, do: raise(ArgumentError, "Integer value is too large to encode")

    case exists_l_in_N8(x) do
      nil -> <<2 ** 8 - 1>> <> encode_le(x, 8)
      l -> <<2 ** 8 - 2 ** (8 - l) + div(x, 2 ** (8 * l))>> <> encode_le(rem(x, 2 ** (8 * l)), l)
    end
  end

  defp encode_list(value) do
    value |> Enum.map(&do_encode/1) |> Enum.join()
  end

  # Formula (279) v0.3.4
  defp encode_bits([]), do: <<>>

  defp encode_bits(bits) do
    {chunk, rest} = Enum.split(bits, 8)

    <<encode_octet(chunk)>> <> encode_bits(rest)
  end

  defp encode_octet(bits) do
    bits
    |> Enum.with_index()
    |> Enum.reduce(0, fn {bit, i}, acc -> acc + bit * 2 ** i end)
  end
end
