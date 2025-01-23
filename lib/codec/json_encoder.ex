defmodule Codec.JsonEncoder do
  import Util.Hex
  def to_json(struct) when is_map(struct) do
    for x <- Map.from_struct(struct), do: encode_field(x), into: %{}
  end

  defp encode_field({key, value}) when is_binary(value) do
    {key, encode16(value, prefix: true)}
  end
end
