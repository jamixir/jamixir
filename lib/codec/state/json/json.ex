defmodule Codec.State.Json do
  alias System.State
  alias System.State.Safrole
  import Codec.State.Json.DecodeField

  @spec decode(any()) :: State.t()
  def decode(json) do
    decoded_fields =
      for {key, value} <- json,
          {struct_key, decoded_value} <- decode_field(key, value),
          into: %{} do
        {struct_key, decoded_value}
      end
      |> merge_safrole_fields()

    struct(State, decoded_fields)
  end

  defp merge_safrole_fields(fields) do
    if fields[:safrole_pending] || fields[:safrole_epoch_root] ||
         fields[:safrole_slot_sealers] || fields[:safrole_ticket_accumulator] do
      safrole =
        Safrole.from_json(%{
          pending: fields[:safrole_pending],
          epoch_root: fields[:safrole_epoch_root],
          slot_sealers: fields[:safrole_slot_sealers],
          ticket_accumulator: fields[:safrole_ticket_accumulator]
        })

      fields
      |> Map.drop([
        :safrole_pending,
        :safrole_epoch_root,
        :safrole_slot_sealers,
        :safrole_ticket_accumulator
      ])
      |> Map.put(:safrole, safrole)
    else
      fields
    end
  end
end
