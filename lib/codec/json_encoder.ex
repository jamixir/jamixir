defmodule Codec.JsonEncoder do
  def to_json(struct) when is_map(struct) do
    for x <- Map.from_struct(struct), do: encode_field(x), into: %{}
  end

  defp encode_field({key, value}) when is_binary(value) do
    {key, "0x" <> Base.encode16(value, case: :lower)}
  end
end
