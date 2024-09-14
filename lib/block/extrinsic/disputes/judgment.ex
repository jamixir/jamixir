defmodule Block.Extrinsic.Disputes.Judgement do
  @moduledoc """
  Formula (98) v0.3.4
  essentialy a vote on the validity of a work report.
  """
  @type t :: %__MODULE__{
          validator_index: Types.validator_index(),
          decision: Types.decision(),
          signature: Types.ed25519_signature()
        }

  defstruct validator_index: 0, decision: true, signature: <<>>

  #Formula (100) v0.3.4
  def signature_base(%__MODULE__{decision: decision}) do
    if decision, do: SigningContexts.jam_valid(), else: SigningContexts.jam_invalid()
  end
end
