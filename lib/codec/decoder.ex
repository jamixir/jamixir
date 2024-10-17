defmodule Codec.Decoder do
  @moduledoc """
  A module for decoding binary data into data structures.
  """
  defp decode_little_endian(<<>>, _), do: 0

  defp decode_little_endian(<<byte::size(8), rest::binary>>, l),
    do: byte + decode_little_endian(rest, l - 1) * 256

  def decode_le(encoded, length), do: decode_little_endian(encoded, length)

  @doc """
  Decodes an integer from its binary encoded form.
  """
  def decode_integer(<<0, _rest::binary>>), do: 0

  def decode_integer(<<byte0, _rest::binary>>) when byte0 in 1..127 do
    byte0
  end

  def decode_integer(<<255, value_bytes::binary-size(8), _rest::binary>>) do
    decode_little_endian(value_bytes, 8)
  end

  def decode_integer(<<byte0, rest::binary>>) when byte0 in 128..254 do
    {l, a_l} = determine_l_and_a_l(byte0)
    h = byte0 - a_l
    x_rest = decode_le(rest, l)
    x = h * :math.pow(256, l) + x_rest
    trunc(x)
  end

  defp determine_l_and_a_l(byte0) do
    cond do
      byte0 >= 254 ->
        {7, 254}

      byte0 >= 252 ->
        {6, 252}

      byte0 >= 248 ->
        {5, 248}

      byte0 >= 240 ->
        {4, 240}

      byte0 >= 224 ->
        {3, 224}

      byte0 >= 192 ->
        {2, 192}

      byte0 >= 128 ->
        {1, 128}
    end
  end

  defmacro __using__(_) do
    quote do
      def de_le(value, l), do: Codec.Decoder.decode_le(value, l)
    end
  end
end
