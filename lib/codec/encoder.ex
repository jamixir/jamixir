defmodule Codec.Encoder do
  @moduledoc """
  A module for encoding data structures into binary format.
  """

  import Bitwise

  @pow_7 128
  @pow_64 18446744073709551616

  @doc """
  Encodes a given value into a binary format.
  """
  @spec encode(any()) :: binary()
  def encode(value) do
    do_encode(value)
  end

  # Private Functions

  defp is_bit_list(bits) do
    Enum.all?(bits, &(&1 in [0, 1]))
  end

  defp do_encode(nil), do: <<0>>
  defp do_encode(value) when is_binary(value), do: value
  defp do_encode(value) when is_list(value) do
    if is_bit_list(value) do
      encode_bits(value)
    else
      encode_list(value)
    end
  end
  defp do_encode(value) when is_integer(value), do: encode_integer(value)
  defp do_encode(value) when is_list(value), do: encode_list(value)
  defp do_encode(value) when is_tuple(value), do: value |> Tuple.to_list() |> encode_list()
  # defp do_encode(%Block.Header{} = header), do: encode_header(header)



  defp determine_level(x) do
    cond do
      x < 1 <<< 14 -> 1
      x < 1 <<< 21 -> 2
      x < 1 <<< 28 -> 3
      true -> 8
    end
  end

  defp encode_bytes(_x, 0), do: <<>>
  defp encode_bytes(x, l), do: <<rem(x, 256)>> <> encode_bytes(div(x, 256), l-1)


  defp encode_integer(x) when x < @pow_7,  do: <<x>>
  defp encode_integer(x) when x < @pow_64 do
    l = determine_level(x)
    shift = 8 * l
    prefix = 256 - (1 <<< (8 - l))
    <<prefix + div(x, 1 <<< shift)>> <> encode_bytes(rem(x, 1 <<< shift), l)
  end




  defp encode_list(value) do
    encoded_elements = Enum.map(value, &do_encode/1)
    encoded_length = encode_integer(length(value))
    encoded_length <> Enum.join(encoded_elements, <<>>)
  end


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
    |> Enum.reduce(0, fn {bit, index}, acc -> acc ||| (bit <<< index) end)
    |> :binary.encode_unsigned()
  end


end
