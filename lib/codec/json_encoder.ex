defmodule Codec.JsonEncoder do
  def to_json(struct) when is_map(struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(&encode_field/1)
    |> Enum.into(%{})
  end

  def to_json(%_{} = struct) do
    # Delegate to Encodable protocol for structs
    JsonEncodable.to_json(struct)
  end

  defp encode_field({key, value}) when is_binary(value) do
    {key, Base.encode16(value, case: :lower)}
  end

  defp encode_field({key, value}) when is_map(value) do
    {key, to_json(value)}
  end

  defp encode_field({key, value}) do
    {key, value}
  end
end
