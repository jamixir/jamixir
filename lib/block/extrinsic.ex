defmodule Block.Extrinsic do
  # Equation (14)
  defstruct tickets: [], judgements: [], preimages: [], availability: [], reports: []

  @type t :: %__MODULE__{
          tickets: list(Ticket.t()), # Et
          judgements: list(Judgement.t()), # Ed
          preimages: list(Preimage.t()), # Ep
          availability: list(Availability.t()), # Ea
          reports: list(Report.t()) # Eg
        }

  @doc """
  Represents the block extrinsic as described.
  E ≡ (ET, EJ, EP, EA, EG)
  """
  def new(tickets, judgements, preimages, availability, reports) do
    %Block.Extrinsic{
      tickets: tickets,
      judgements: judgements,
      preimages: preimages,
      availability: availability,
      reports: reports
    }
  end
end
