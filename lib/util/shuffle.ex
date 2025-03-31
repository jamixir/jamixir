defmodule Shuffle do
  use Codec.Encoder
  # Formula (F.1) v0.6.4
  @spec shuffle(list(any()), list(integer()) | Types.hash()) :: list(any())
  def shuffle([], _), do: []

  def shuffle(list, r)
      when is_list(r) and length(r) >= length(list) do
    l = length(list)
    i = rem(Enum.at(r, 0), l)
    element = Enum.at(list, i)
    new_list = List.replace_at(list, i, Enum.at(list, l - 1))
    [element | shuffle(Enum.take(new_list, l - 1), Enum.drop(r, 1))]
  end

  # Formula (F.3) v0.6.4
  def shuffle(list, hash) when is_binary(hash) and bit_size(hash) == 256 do
    shuffle(list, hash_to_sequence(hash, length(list)))
  end

  use Codec.Decoder

  # Formula (F.2) v0.6.4
  defp hash_to_sequence(hash, l) do
    for i <- 0..l do
      <<n::32-little>> = :binary.part(h(hash <> e_le(div(i, 8), 4)), rem(4 * i, 32), 4)
      n
    end
  end
end
