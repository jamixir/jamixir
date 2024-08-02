defmodule Disputes.Culprit do
  @moduledoc """
  Culprits represent validators who have guaranteed incorrect reports.
  """

  alias Types
  alias Util.Crypto

  @type t :: %__MODULE__{
          work_report_hash: Types.hash(),
          validator_key: Types.ed25519_key(),
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, validator_key: <<>>, signature: <<>>

  @doc """
  Checks if the given signature is valid for the given validator key.
  """
  def valid_signature?(%__MODULE__{
        work_report_hash: work_report_hash,
        signature: signature,
        validator_key: key
      }) do
    Crypto.verify_signature(signature, work_report_hash, key)
  end
end
