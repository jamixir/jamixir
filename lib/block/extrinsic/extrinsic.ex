defmodule Block.Extrinsic do
  alias Block.Extrinsic.{Disputes, Guarantee}
  # Formula (14) v0.3.4
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
  def unique_sorted_guarantees(%Block.Extrinsic{guarantees: guarantees}) do
    # Check for duplicate core_index before sorting
    if Util.Collections.has_duplicates?(guarantees, & &1.work_report.core_index) do
      raise ArgumentError, "Duplicate core_index found in guarantees"
    end

    sorted_guarantees =
      guarantees
      |> Enum.map(fn guarantee ->
        # Check for duplicate validator_index before sorting credentials
        if Util.Collections.has_duplicates?(guarantee.credential, &elem(&1, 0)) do
          raise ArgumentError, "Duplicate validator_index found in credentials"
        end

        sorted_credentials = Enum.sort_by(guarantee.credential, &elem(&1, 0))

        %Guarantee{
          guarantee
          | credential: sorted_credentials
        }
      end)
      |> Enum.sort_by(& &1.work_report.core_index)

    sorted_guarantees
  end

  defimpl Encodable do
    def vs(arg), do: Codec.VariableSize.new(arg)

    def encode(%Block.Extrinsic{} = e) do
      Codec.Encoder.encode(
        {vs(e.tickets), e.disputes, vs(e.preimages), vs(e.availability), vs(e.guarantees)}
      )
    end
  end
end
