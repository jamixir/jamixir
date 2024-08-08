defmodule Block.Extrinsic do
  alias Disputes
  # Equation (14)
  defstruct tickets: [], disputes: nil, preimages: [], availability: [], guarantees: []

  alias Block.Extrinsics.{Guarantee}

  @type t :: %__MODULE__{
          tickets: list(Ticket.t()),
          disputes: Disputes.t(),
          preimages: list(Preimage.t()),
          availability: list(Availability.t()),
          # Eg
          guarantees: list(Guarantee.t())
        }

  @doc """
  Represents the block extrinsic as described.
  E ≡ (ET, ED, EP, EA, EG)
  """
  def new(tickets, disputes, preimages, availability, guarantees) do
    %Block.Extrinsic{
      tickets: tickets,
      disputes: disputes,
      preimages: preimages,
      availability: availability,
      guarantees: guarantees
    }
  end
end
