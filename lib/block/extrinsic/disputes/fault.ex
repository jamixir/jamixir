defmodule Block.Extrinsic.Disputes.Fault do
  @moduledoc """
  Fomrula 98 v0.3.4
  Faults represent validators who have signed  a judgement that was found to be in
  cotradiction with the work-report's validity.
  """
  alias Types

  @type t :: %__MODULE__{
          work_report_hash: Types.hash(),
          decision: Types.decision(),
          validator_key: Types.ed25519_key(),
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, decision: true, validator_key: <<>>, signature: <<>>
end
