defmodule Codec.JsonEncoder do
  def to_json(struct) when is_map(struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(&encode_field/1)
    |> Enum.into(%{})
  end

  defp encode_field({key, value}) when is_binary(value) do
    {key, "0x" <> Base.encode16(value, case: :lower)}
  end
end
