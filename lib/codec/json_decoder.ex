defmodule JsonDecoder do
  def from_json(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {key, from_json(value)}
    end)
    |> Enum.into(%{})
  end

  def from_json(list) when is_list(list) do
    list |> Enum.map(&from_json/1)
  end

  def from_json(nil), do: nil

  def from_json(value) when is_binary(value) do
    case Base.decode16(String.replace_prefix(value, "0x", ""), case: :lower) do
      {:ok, binary} ->
        binary

      :error ->
        value
    end
  end

  def from_json(value), do: value

  def to_struct(module, json_data) do
    mapping = module.json_mapping()

    values =
      Enum.map(Utils.list_struct_fields(module), fn field ->
        {field,
         case mapping[field] do
           nil ->
             JsonDecoder.from_json(json_data[field])

           value when is_atom(value) ->
             if Code.ensure_loaded?(value) and function_exported?(value, :from_json, 1) do
               value.from_json(json_data[field])
             else
               JsonDecoder.from_json(json_data[value])
             end
         end}
      end)
      |> Enum.into(%{})

    struct(module, values)
  end

  defmacro __using__(_) do
    quote do
      def from_json(json) do
        JsonDecoder.to_struct(__MODULE__, json)
      end
    end
  end
end
