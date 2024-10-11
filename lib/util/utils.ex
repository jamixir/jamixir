defmodule Utils do
  import Bitwise

  def hex_to_binary(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {key, hex_to_binary(value)}
    end)
    |> Enum.into(%{})
  end

  def hex_to_binary(list) when is_list(list) do
    list |> Enum.map(&hex_to_binary/1)
  end

  def hex_to_binary(value) when is_binary(value) do
    case Base.decode16(String.replace_prefix(value, "0x", ""), case: :lower) do
      {:ok, binary} ->
        binary

      :error ->
        value
    end
  end

  def hex_to_binary(value), do: value

  def atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      if is_atom(key) do
        {key, value}
      else
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> String.to_atom(key)
          end

        {atom_key, value}
      end
    end)
    |> Enum.into(%{})
  end

  def atomize_keys(value), do: value

  def invert_bits(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(&(bnot(&1) &&& 0xFF))
    |> :binary.list_to_bin()
  end

  def get_bit(bitstring, index)
      when is_bitstring(bitstring) and is_integer(index) and index >= 0 do
    bit_size = bit_size(bitstring)

    if index >= bit_size do
      0
    else
      <<_::size(index), bit::1, _::bitstring>> = bitstring
      bit
    end
  end
end
