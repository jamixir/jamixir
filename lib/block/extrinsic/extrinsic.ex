defmodule Block.Extrinsic do
  alias Block.Extrinsic.{Assurance, Disputes, Guarantee, Preimage, TicketProof}
  # Formula (14) v0.4.1
  defstruct tickets: [], disputes: %Disputes{}, preimages: [], assurances: [], guarantees: []

  @type t :: %__MODULE__{
          tickets: list(TicketProof.t()),
          disputes: Disputes.t(),
          # Formula (154) v0.4.1
          preimages: list(Preimage.t()),
          assurances: list(Assurance.t()),
          # Eg
          guarantees: list(Guarantee.t())
        }

  @spec validate(t(), Block.Header.t(), System.State.t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = extrinsic, header, %System.State{} = state) do
    with :ok <- Guarantee.validate(extrinsic.guarantees, state, header.timeslot),
         :ok <-
           TicketProof.validate(
             extrinsic.tickets,
             header.timeslot,
             state.timeslot,
             state.entropy_pool,
             state.safrole
           ),
         :ok <-
           Disputes.validate(
             extrinsic.disputes,
             state.curr_validators,
             state.prev_validators,
             state.judgements,
             header.timeslot
           ),
         :ok <- Preimage.validate(extrinsic.preimages, state.services) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defimpl Encodable do
    def vs(arg), do: Codec.VariableSize.new(arg)

    def encode(%Block.Extrinsic{} = e) do
      Codec.Encoder.encode(
        {vs(e.tickets), e.disputes, vs(e.preimages), vs(e.assurances), vs(e.guarantees)}
      )
    end
  end

  def from_json(json_data) do
    %__MODULE__{
      tickets: Enum.map(json_data[:extrinsic], &TicketProof.from_json/1)
    }
  end
end
