defmodule Block.Extrinsic.Disputes.Culprit do
  @moduledoc """
  Formula (98) v0.4.1
  Culprits represent validators who have guaranteed incorrect reports.
  """

  alias Types

  @type t :: %__MODULE__{
          # r
          work_report_hash: Types.hash(),
          # k
          validator_key: Types.ed25519_key(),
          # s
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, validator_key: <<>>, signature: <<>>
end
