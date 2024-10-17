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
          key: Types.ed25519_key(),
          # s
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, key: <<>>, signature: <<>>

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Extrinsic.Disputes.Culprit

    def encode(d = %Culprit{}) do
      e({d.work_report_hash, d.key, d.signature})
    end
  end

  use Sizes

  @spec decode(binary()) :: {Block.Extrinsic.Disputes.Culprit.t(), binary()}
  def decode(blob) do
    <<work_report_hash::binary-size(@hash_size), key::binary-size(@hash_size),
      signature::binary-size(@signature_size), rest::binary>> = blob

    {
      %__MODULE__{work_report_hash: work_report_hash, key: key, signature: signature},
      rest
    }
  end

  use JsonDecoder

  def json_mapping, do: %{work_report_hash: :target}
end
