defmodule Block.Extrinsic.Disputes.Culprit do
  @moduledoc """
  Culprits represent validators who have guaranteed incorrect reports.
  """

  alias Types

  @type t :: %__MODULE__{
          work_report_hash: Types.hash(),
          validator_key: Types.ed25519_key(),
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, validator_key: <<>>, signature: <<>>
end
