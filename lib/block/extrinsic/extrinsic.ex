defmodule Block.Extrinsic do
  alias Codec.VariableSize
  alias Block.Extrinsic.{Assurance, Disputes, Guarantee, Preimage, TicketProof}
  # Formula (4.3) v0.6.5
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
    with :ok <- Guarantee.validate(extrinsic.guarantees, state, header),
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

    # Formula (C.13) v0.6.5
    def encode(%Block.Extrinsic{} = ex),
      do:
        e({
          # Formula (C.14) v0.6.5
          vs(ex.tickets),
          # Formula (C.15) v0.6.5
          vs(ex.preimages),
          # Formula (C.16) v0.6.5
          vs(ex.guarantees),
          # Formula (C.17) v0.6.5
          vs(ex.assurances),
          # Formula (C.18) v0.6.5
          ex.disputes
        })
  end

  use Codec.Encoder
  # Formula (5.4) v0.6.5
  # Formula (5.5) v0.6.5
  # Formula (5.6) v0.6.5
  def calculate_hash(%Block.Extrinsic{} = ex) do
    a = [
      e(vs(ex.tickets)),
      e(vs(ex.preimages)),
      g(ex.guarantees),
      e(vs(ex.assurances)),
      e(ex.disputes)
    ]

    h(e(for el <- a, do: h(el)))
  end

  # Formula (5.6) v0.6.5
  def g(guarantees) do
    e(
      vs(
        for %Guarantee{work_report: w, timeslot: timeslot, credentials: a} <- guarantees do
          e({h(e(w)), t(timeslot), Guarantee.encode_credentials(a)})
        end
      )
    )
  end

  use JsonDecoder

  def decode(bin) do
    {tickets, bin} = VariableSize.decode(bin, TicketProof)
    {preimages, bin} = VariableSize.decode(bin, Preimage)
    {guarantees, bin} = VariableSize.decode(bin, Guarantee)
    {assurances, bin} = VariableSize.decode(bin, Assurance)
    {disputes, bin} = Disputes.decode(bin)

    {%__MODULE__{
       tickets: tickets,
       disputes: disputes,
       preimages: preimages,
       assurances: assurances,
       guarantees: guarantees
     }, bin}
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
