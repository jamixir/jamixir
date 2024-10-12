defmodule Block.Extrinsic.Disputes.Fault do
  @moduledoc """
  Formula (98) v0.4.1
  Faults represent validators who have signed  a judgement that was found to be in
  cotradiction with the work-report's validity.
  """
  alias Types

  @type t :: %__MODULE__{
          # r
          work_report_hash: Types.hash(),
          # v
          decision: Types.decision(),
          # k
          validator_key: Types.ed25519_key(),
          # s
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, decision: true, validator_key: <<>>, signature: <<>>

  defimpl Encodable do
    alias Block.Extrinsic.Disputes.Fault

    def encode(f = %Fault{}) do
      dec = if f.decision, do: 1, else: 0
      Codec.Encoder.encode({f.work_report_hash, dec, f.validator_key, f.signature})
    end
  end

  use JsonDecoder
  def json_mapping, do: %{work_report_hash: :target, decision: :vote, validator_key: :key}
end
