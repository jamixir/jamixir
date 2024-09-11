defmodule Utils do
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
    case Base.decode16(value, case: :lower) do
      {:ok, binary} -> binary
      :error -> value
    end
  end

  def hex_to_binary(value), do: value
end
