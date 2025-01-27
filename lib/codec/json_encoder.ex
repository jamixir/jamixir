defmodule Codec.JsonEncoder do
  import Util.Hex

  def encode(%{__struct__: module} = struct) do
    # Get key mappings if module has them, otherwise empty map
    key_mapping =
      if function_exported?(module, :to_json_mapping, 0), do: module.to_json_mapping(), else: %{}

    # Start with struct-to-map conversion
    base =
      struct
      |> Map.from_struct()
      # Remove keys that will be transformed
      |> Map.drop(Map.keys(key_mapping))

    # Handle root transformation separately
    case Enum.find(key_mapping, fn {_, mapping} -> match?({:_root, _}, mapping) or mapping == :_root end) do
      {key, {:_root, transform}} ->
        transform.(Map.get(struct, key)) |> encode()

      {key, :_root} ->
        encode(Map.get(struct, key))

      _ ->
        # Normal field transformations
        transformed =
          for {old_key, mapping} <- key_mapping, into: %{} do
            original_value = Map.get(struct, old_key)

            case mapping do
              {new_key, transform} -> {new_key, transform.(original_value)}
              new_key when is_atom(new_key) -> {new_key, original_value}
            end
          end

        Map.merge(base, transformed) |> Map.new(fn {k, v} -> {k, encode(v)} end)
    end
  end

  def encode(value) when is_list(value), do: Enum.map(value, &encode/1)
  def encode(value) when is_map(value), do: for({k, v} <- value, into: %{}, do: {k, encode(v)})
  def encode(value) when is_binary(value), do: encode16(value, prefix: true)
  def encode(value), do: value

  defmacro __using__(_) do
    quote do
      def to_json(struct), do: JsonEncoder.encode(struct)
    end
  end
end
