defmodule System.State.SealKeyTicket do
  @moduledoc """
  represent a ticket, as specified in section 6.2 of the GP.
  Formula (51) v0.3.4
  """
  alias Block.Header
  alias System.State.EntropyPool

  @type t :: %__MODULE__{
          id: Types.hash(),
          entry_index: non_neg_integer()
        }

  defstruct id: <<>>, entry_index: 0

  def validate_candidate(
        %__MODULE__{id: ticket_id, entry_index: entry_index},
        %Header{block_author_key_index: h_i, block_seal: h_s} = header,
        %EntropyPool{history: [_, _, eta3 | _]},
        curr_validators
      ) do
    with %System.State.Validator{bandersnatch: key} <- Enum.at(curr_validators, h_i),
         message = Header.unsigned_serialize(header),
         aux_data = SigningContexts.jam_ticket_seal() <> eta3 <> Integer.to_string(entry_index),
         {:ok, computed_ticket_id} <-
           Util.Bandersnatch._verify(key, message, aux_data, h_s),
         true <- computed_ticket_id == ticket_id do
      :ok
    else
      nil ->
        {:error, :invalid_validator_index}

      {:error, reason} ->
        {:error, reason}

      false ->
        {:error, :invalid_ticket_id}
    end
  end

  defimpl Encodable do
    # Formula (289) v0.3.4
    def encode(%System.State.SealKeyTicket{} = e) do
      Codec.Encoder.encode({
        e.id,
        e.entry_index
      })
    end
  end
end
