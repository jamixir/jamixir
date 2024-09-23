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
    for {key, val} <- map, into: %{} do
      {String.to_existing_atom(to_string(key)), atomize_keys(val)}
    end
  end

  def atomize_keys(value), do: value

  def invert_bits(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(&(bnot(&1) &&& 0xFF))
    |> :binary.list_to_bin()
  end
end
