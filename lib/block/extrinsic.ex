defmodule Block.Extrinsic do
  # Equation (14)
  defstruct tickets: [], judgements: [], preimages: [], availability: [], reports: []

  @type t :: %__MODULE__{
          # Et
          tickets: list(Ticket.t()),
          # Ed
          judgements: list(Judgement.t()),
          # Ep
          preimages: list(Preimage.t()),
          # Ea
          availability: list(Availability.t()),
          # Eg
          reports: list(Report.t())
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
