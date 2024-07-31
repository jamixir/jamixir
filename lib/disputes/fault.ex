defmodule Disputes.Fault do
  alias Types

  @type t :: %__MODULE__{
          work_report_hash: Types.hash(),
          decision: Types.decision(),
          validator_key: Types.ed25519_key(),
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, decision: true, validator_key: <<>>, signature: <<>>

  @doc """
  Checks if the given signature is valid for the given validator key.
  """
  def valid_signature?(%__MODULE__{
        work_report_hash: work_report_hash,
        signature: signature,
        validator_key: key
      }) do
    :crypto.verify(:eddsa, :none, work_report_hash, signature, [key, :ed25519])
  end
end
