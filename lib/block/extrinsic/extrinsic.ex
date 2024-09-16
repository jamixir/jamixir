defmodule Block.Extrinsic do
  alias Block.Extrinsic.Preimage
  alias Block.Extrinsic.{Disputes, Guarantee, TicketProof}
  alias Util.Collections
  # Formula (14) v0.3.4
  defstruct tickets: [], disputes: %Disputes{}, preimages: [], assurances: [], guarantees: []

  @type t :: %__MODULE__{
          tickets: list(TicketProof.t()),
          disputes: Disputes.t(),
          # Formula (155) v0.3.4
          preimages: list(Preimage.t()),
          assurances: list(Assurance.t()),
          # Eg
          guarantees: list(Guarantee.t())
        }


        # Formula (138) v0.3.4
        # Formula (139) v0.3.4
        # Formula (140) v0.3.4
  def validate_guarantees(guarantees) do
    with :ok <- Collections.validate_unique_and_ordered(guarantees, & &1.work_report.core_index),
         true <-
           Enum.all?(guarantees, fn %Guarantee{credential: cred} ->
             length(cred) in [2, 3]
           end),
         true <-
           Collections.all_ok?(guarantees, fn %Guarantee{credential: cred} ->
             Collections.validate_unique_and_ordered(cred, &elem(&1, 0))
           end) do
      :ok
    else
      {:error, :duplicates} -> {:error, "Duplicate core_index found in guarantees"}
      {:error, :not_in_order} -> {:error, "Guarantees not ordered by core_index"}
      false -> {:error, "Invalid credentials in one or more guarantees"}
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
end
