defmodule Block do
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
    with :ok <- Block.Header.validate(header, state),
         :ok <- Block.Extrinsic.validate_guarantees(extrinsic.guarantees),
         :ok <-
          Block.Extrinsic.Disputes.validate_disputes(
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
