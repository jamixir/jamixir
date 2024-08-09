defmodule Codec.Encoder do
  @moduledoc """
  A module for encoding data structures into binary format.
  """

  import Bitwise

  @doc """
  Encodes a given value into a binary format.
  """
  @spec encode(any()) :: binary()
  def encode(value) do
    do_encode(value)
  end

  # Equation (271)
  def encode_little_endian(_, 0), do: <<>>

  def encode_little_endian(x, l) do
    <<rem(x, 256)>> <> encode_little_endian(div(x, 256), l - 1)
  end

  def encode_le(x, l), do: encode_little_endian(x, l)

  # Private Functions

  defp is_bit_list(bits) do
    Enum.all?(bits, &(&1 in [0, 1]))
  end

  # Equation (267)
  defp do_encode(nil), do: <<>>
  # Equation (268)
  defp do_encode(value) when is_binary(value), do: value
  # Equation (269)
  defp do_encode(value) when is_tuple(value), do: value |> Tuple.to_list() |> encode_list()
  # Equation (270) is not implementable in Elixir,
  # as it does not have a built-in arbitrary number of arguments in functions

  defp do_encode(value) when is_list(value) do
    if is_bit_list(value) do
      encode_bits(value)
    else
      encode_list(value)
    end
  end

  defp do_encode(value) when is_integer(value), do: encode_integer(value)
  defp do_encode(value) when is_list(value), do: encode_list(value)
  # defp do_encode(%Block.Header{} = header), do: encode_header(header)

  # l = 0 => 2 < x < 2^7
  # l = 1 => 2^7 <= x < 2^14
  # l = 2 => 2^14 <= x < 2^21
  # ...
  # l = 7 => 2^49 <= x < 2^56
  defp exists_l_in_N8(x) do
    # TODO maybe there is a more efficient way to implement this
    Enum.find(0..7, fn l ->
      x >= 2 ** (7 * l) and
        x < 2 ** (7 * (l + 1))
    end)
  end

  # Equation (273)
  defp encode_integer(0), do: <<0>>

  # Equation (273)
  defp encode_integer(x) do
    if x >= 2 ** 64, do: raise(ArgumentError, "Integer value is too large to encode")

    case exists_l_in_N8(x) do
      nil -> <<2 ** 8 - 1>> <> encode_le(x, 8)
      l -> <<2 ** 8 - 2 ** (8 - l) + div(x, 2 ** (8 * l))>> <> encode_le(rem(x, 2 ** (8 * l)), l)
    end
  end

  defp encode_list(value) do
    encoded_elements = Enum.map(value, &do_encode/1)
    Enum.join(encoded_elements, <<>>)
  end

  # Equation (277)
  defp encode_bits([]), do: <<>>

  defp encode_bits(bits) do
    bits
    |> Enum.chunk_every(8)
    |> Enum.map(&encode_octet/1)
    |> Enum.join()
  end

  defp encode_octet(bits) do
    bits
    |> Enum.with_index()
    |> Enum.reduce(0, fn {bit, index}, acc -> acc ||| bit <<< index end)
    |> :binary.encode_unsigned()
  end
end
