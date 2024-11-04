defmodule Block.Extrinsic do
  alias Codec.VariableSize
  alias Block.Extrinsic.{Assurance, Disputes, Guarantee, Preimage, TicketProof}
  # Formula (14) v0.4.5
  defstruct tickets: [], disputes: %Disputes{}, preimages: [], assurances: [], guarantees: []

  @type t :: %__MODULE__{
          # ET
          tickets: list(TicketProof.t()),
          # ED
          disputes: Disputes.t(),
          # EP
          preimages: list(Preimage.t()),
          # EA
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
             state.timeslot
           ),
         :ok <- Preimage.validate(extrinsic.preimages, state.services) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defimpl Encodable do
    use Codec.Encoder

    def encode(%Block.Extrinsic{} = ex) do
      e({vs(ex.tickets), ex.disputes, vs(ex.preimages), vs(ex.assurances), vs(ex.guarantees)})
    end
  end

  use JsonDecoder

  def decode(bin) do
    {tickets, bin} = VariableSize.decode(bin, TicketProof)
    {disputes, bin} = Disputes.decode(bin)
    {preimages, bin} = VariableSize.decode(bin, Preimage)
    {assurances, bin} = VariableSize.decode(bin, Assurance)
    {guarantees, rest} = VariableSize.decode(bin, Guarantee)

    {%__MODULE__{
       tickets: tickets,
       disputes: disputes,
       preimages: preimages,
       assurances: assurances,
       guarantees: guarantees
     }, rest}
  end

  def json_mapping,
    do: %{
      tickets: [TicketProof],
      disputes: Disputes,
      preimages: [Preimage],
      assurances: [Assurance],
      guarantees: [Guarantee]
    }
end
