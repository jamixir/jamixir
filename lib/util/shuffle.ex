defmodule Shuffle do
  # Formula (306) v0.3.4
  @spec shuffle(list(any()), list(integer()) | Types.hash()) :: list(any())
  def shuffle([], _), do: []

  def shuffle(list, numeric_sequence)
      when is_list(numeric_sequence) and length(numeric_sequence) >= length(list) do
    i = rem(Enum.at(numeric_sequence, 0), length(list))
    {element, new_list} = List.pop_at(list, i)
    [element | shuffle(new_list, Enum.drop(numeric_sequence, 1))]
  end

  # Formula (308) v0.3.4
  def shuffle(list, hash) when is_binary(hash) and bit_size(hash) == 256 do
    shuffle(list, transform_hash_into_sequence(hash, length(list)))
  end

  # Formula (307) v0.3.4
  defp transform_hash_into_sequence(hash, sequence_length) do
    numeric_sequence =
      Enum.reduce(0..(sequence_length - 1), [], fn i, acc ->
        encoded_chunk = Codec.Encoder.encode_little_endian(div(i, 8), 4)
        new_hash = Util.Hash.blake2b_256(hash <> encoded_chunk)
        encoded_numeric_position = :binary.part(new_hash, rem(4 * i, 32), 4)
        decoded_numeric_position = Codec.Decoder.decode_le(encoded_numeric_position, 4)
        acc ++ [decoded_numeric_position]
      end)

    numeric_sequence
  end
end
