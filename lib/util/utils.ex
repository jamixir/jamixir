defmodule Utils do
  import Bitwise

  def list_struct_fields(module) do
    module.__struct__()
    |> Map.keys()
    |> Enum.reject(&(&1 == :__struct__))
  end

  defp safe_to_existing_atom(string) do
    try do
      String.to_existing_atom(string)
    rescue
      ArgumentError -> {:error, :not_existing_atom}
    end
  end

  def atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      case safe_to_existing_atom(key) do
        {:error, :not_existing_atom} -> {String.to_atom(key), atomize_keys(value)}
        atom -> {atom, atomize_keys(value)}
      end
    end)
    |> Enum.into(%{})
  end

  def atomize_keys(list) when is_list(list) do
    list |> Enum.map(&atomize_keys/1)
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

  def pad_binary(value, size) when byte_size(value) < size do
    padding = size - byte_size(value)
    <<0::size(padding * 8)>> <> value
  end

  def pad_binary(value, _size), do: value

  def zero_bitstring(size) do
    String.duplicate(<<0>>, size)
  end
end
