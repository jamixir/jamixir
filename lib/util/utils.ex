defmodule Utils do
  import Bitwise
  import RangeMacros

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
    for {key, value} <- map, into: %{} do
      case safe_to_existing_atom(key) do
        {:error, :not_existing_atom} -> {String.to_atom(key), atomize_keys(value)}
        atom -> {atom, atomize_keys(value)}
      end
    end
  end

  def atomize_keys(list) when is_list(list) do
    for x <- list, do: atomize_keys(x)
  end

  def atomize_keys(value), do: value

  def invert_bits(binary) when is_binary(binary) do
    for b <- :binary.bin_to_list(binary) do
      bnot(b) &&& 0xFF
    end
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

  # Formula (208) v0.4.5
  def pad_binary_right(x, n) do
    start = rem(byte_size(x) + n - 1, n) + 1
    pad = for _ <- from_0_to(n - start), into: <<>>, do: <<0>>
    x <> pad
  end

  def zero_bitstring(size) do
    String.duplicate(<<0>>, size)
  end

  def transpose_binaries(binaries) do
    binaries
    |> Enum.map(&:binary.bin_to_list/1)
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.map(&:binary.list_to_bin/1)
  end

  def keys_set(map), do: MapSet.new(Map.keys(map))
end
