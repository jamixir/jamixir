defmodule Block.Extrinsic do
  alias Block.Extrinsic.{Disputes, Guarantee}
  # Equation (14)
  defstruct tickets: [], disputes: nil, preimages: [], availability: [], guarantees: []

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

  @doc """
  Returns the list of guarantees ordered by work_report.core_index.
  Within each guarantee, the credentials are ordered by validator_index.
  Ensures that the core_index in guarantees and validator_index in credentials are unique.
  """
  def guarantees(%Block.Extrinsic{guarantees: guarantees}) do
    sorted_guarantees =
      guarantees
      |> Enum.sort_by(& &1.work_report.core_index)
      |> Enum.map(fn guarantee ->
        sorted_credentials = Enum.sort_by(guarantee.credential, &elem(&1, 0))

        if Enum.uniq_by(sorted_credentials, &elem(&1, 0)) != sorted_credentials do
          raise ArgumentError, "Duplicate validator_index found in credentials"
        end

        %Guarantee{
          guarantee
          | credential: sorted_credentials
        }
      end)

    if Enum.uniq_by(sorted_guarantees, & &1.work_report.core_index) != sorted_guarantees do
      raise ArgumentError, "Duplicate core_index found in guarantees"
    end

    sorted_guarantees
  end
end
