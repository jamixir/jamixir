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

  defimpl Encodable do
    alias Block.Extrinsic.Disputes.Culprit

    def encode(d = %Culprit{}) do
      Codec.Encoder.encode({d.work_report_hash, d.validator_key, d.signature})
    end
  end

  use JsonDecoder

  def json_mapping, do: %{work_report_hash: :target, validator_key: :key}
end
