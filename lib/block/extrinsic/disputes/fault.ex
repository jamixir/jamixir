defmodule Block.Extrinsic.Disputes.Fault do
  @moduledoc """
  Formula (98) v0.3.4
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
end
