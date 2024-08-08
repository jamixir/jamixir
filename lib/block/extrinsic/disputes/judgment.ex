defmodule Block.Extrinsic.Disputes.Judgement do
  @type t :: %__MODULE__{
          validator_index: Types.validator_index(),
          decision: Types.decision(),
          signature: Types.ed25519_signature()
        }

  defstruct validator_index: 0, decision: true, signature: <<>>
end
