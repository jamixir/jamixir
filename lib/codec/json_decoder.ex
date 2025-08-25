defmodule JsonDecoder do
  import Util.Hex
  def from_json(nil), do: nil

  def from_json(map) when is_map(map) do
    for {key, value} <- map, do: {key, from_json(value)}, into: %{}
  end

  def from_json(list) when is_list(list) do
    for a <- list, do: from_json(a)
  end

  def from_json(value) when is_binary(value) do
    case decode16(value) do
      {:ok, binary} ->
        binary

      :error ->
        value
    end
  end

  def from_json(value), do: value

  def to_struct(module, json_data) do
    mapping =
      if function_exported?(module, :json_mapping, 0) do
        module.json_mapping()
      else
        %{}
      end

    values =
      for field <- Utils.list_struct_fields(module), into: %{} do
        {field,
         case mapping[field] do
           nil ->
             JsonDecoder.from_json(json_data[field])

           [module] ->
             Enum.map(json_data[field], &module.from_json/1)

           [[module], f] ->
             case json_data[f] do
               nil -> nil
               v -> Enum.map(v, &module.from_json/1)
             end

           {:_custom, fun} ->
             fun.(json_data)

           %{m: module, f: f} ->
             module.from_json(json_data[f])

           f when is_tuple(f) ->
             get_in(json_data, Tuple.to_list(f))

           [f, field] when is_function(f, 1) ->
             f.(json_data[field])

           f when is_function(f, 1) ->
             f.(json_data[field])

           [value, default] when is_atom(value) ->
             JsonDecoder.from_json(json_data[value]) || default

           value when is_atom(value) ->
             if Code.ensure_loaded?(value) and function_exported?(value, :from_json, 1) do
               value.from_json(json_data[field])
             else
               JsonDecoder.from_json(json_data[value])
             end
         end}
      end

    struct(module, values)
  end

  defmacro __using__(_) do
    quote do
      def from_json(nil), do: nil

      def from_json(json) do
        JsonDecoder.to_struct(__MODULE__, json)
      end
    end
  end
end
