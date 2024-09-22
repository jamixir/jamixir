defmodule Block do
  alias Block.Extrinsic
  alias Block.Extrinsic.{Assurance, Disputes}
  alias Block.Header
  alias System.State

  @type t :: %__MODULE__{header: Block.Header.t(), extrinsic: Block.Extrinsic.t()}

  # Formula (13) v0.3.4
  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: nil
  ]

  @spec validate(t(), System.State.t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{header: h, extrinsic: e}, %State{} = s) do
    with :ok <- Header.validate(h, s),
         :ok <- Extrinsic.validate_guarantees(e.guarantees),
         :ok <-
           Disputes.validate_disputes(
             e.disputes,
             s.curr_validators,
             s.prev_validators,
             s.judgements,
             h.timeslot
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defimpl Encodable do
    def encode(%Block{extrinsic: e, header: h}) do
      # Formula (280) v0.3.4
      Codec.Encoder.encode({h, e})
    end
  end
end
