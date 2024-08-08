defmodule Block.Extrinsic.Disputes.Fault do
  alias Types

  @type t :: %__MODULE__{
          work_report_hash: Types.hash(),
          decision: Types.decision(),
          validator_key: Types.ed25519_key(),
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, decision: true, validator_key: <<>>, signature: <<>>
end
