defmodule Extrinsic do
  defstruct tickets: [], judgements: [], preimages: [], availability: [], reports: []

  @type t :: %__MODULE__{
		  tickets: list(Ticket.t()),
		  judgements: list(Judgement.t()),
		  preimages: list(Preimage.t()),
		  availability: list(Availability.t()),
		  reports: list(Report.t())
		}

  @doc """
  Represents the block extrinsic as described.
  E ≡ (ET, EJ, EP, EA, EG)
  """
  def new(tickets, judgements, preimages, availability, reports) do
    %Extrinsic{
      tickets: tickets,
      judgements: judgements,
      preimages: preimages,
      availability: availability,
      reports: reports
    }
  end
end