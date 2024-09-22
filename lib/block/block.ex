defmodule Block do
  alias Block.Extrinsic
  alias Block.Extrinsic.{Assurance, Disputes}
  alias Block.Header

  @type t :: %__MODULE__{
          header: Block.Header.t(),
          extrinsic: Block.Extrinsic.t()
        }

  # Formula (13) v0.3.4
  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: nil
  ]

  @spec validate(t(), System.State.t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{header: header, extrinsic: extrinsic}, state) do
    with :ok <- Header.validate(header, state),
         :ok <- Extrinsic.validate_guarantees(extrinsic.guarantees),
         :ok <-
           Assurance.validate_assurances(
             extrinsic.assurances,
             header.parent_hash,
             state.curr_validators
           ),
         :ok <-
           Disputes.validate_disputes(
             extrinsic.disputes,
             state.curr_validators,
             state.prev_validators,
             state.judgements,
             header.timeslot
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defimpl Encodable do
    def encode(%Block{extrinsic: e, header: h}) do
      # Formula (280) v0.3.4
      Codec.Encoder.encode({
        h,
        e
      })
    end
  end
end
