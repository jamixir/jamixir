defmodule Codec.Decoder do
  use Sizes

  defp decode_little_endian(binary, l) do
    case binary do
      <<num::size(l)-unit(8)-little, _rest::binary>> -> num
      _ -> 0
    end
  end

  def decode_le(encoded, length), do: decode_little_endian(encoded, length)

  def decode_integer(<<0, rest::binary>>), do: {0, rest}

  def decode_integer(<<byte0, rest::binary>>) when byte0 in 1..127 do
    {byte0, rest}
  end

  def decode_integer(<<255, value_bytes::binary-size(8), rest::binary>>) do
    {decode_little_endian(value_bytes, 8), rest}
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

  def decode_list(bin, :hash), do: do_decode_hashes(bin, [])

  def decode_list(bin, :hash, list_length), do: do_decode_hashes(bin, :hash, list_length)

  def decode_list(bin, list_length, decoder_cb) when is_function(decoder_cb, 1) do
    Enum.reduce(1..list_length, {[], bin}, fn _, {acc, remaining} ->
      {value, rest} = decoder_cb.(remaining)
      {acc ++ [value], rest}
    end)
  end

  def decode_list(bin, list_length, module) do
    Enum.reduce(1..list_length, {[], bin}, fn _, {acc, remaining} ->
      {value, rest} = module.decode(remaining)
      {acc ++ [value], rest}
    end)
  end

  defp do_decode_hashes(bin, :hash, list_length) do
    Enum.reduce(1..list_length, {[], bin}, fn _, {acc, remaining} ->
      <<value::binary-size(@hash_size), rest::binary>> = remaining
      {acc ++ [value], rest}
    end)
  end

  defp do_decode_hashes(<<hash::binary-size(@hash_size), rest::binary>>, acc) do
    do_decode_hashes(rest, acc ++ [hash])
  end

  defp do_decode_hashes(_, acc), do: acc

  defmacro __using__(_) do
    quote do
      def de_le(value, l), do: Codec.Decoder.decode_le(value, l)
    end
  end
end
