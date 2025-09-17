defmodule Block.Extrinsic.Disputes.Culprit do
  # Formula (10.2) v0.7.2
  alias Types
  import Codec.Encoder

  # Formula (10.8) v0.7.2
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
    import Codec.Encoder
    alias Block.Extrinsic.Disputes.Culprit

    def encode(%Culprit{} = d) do
      e({d.work_report_hash, d.key, d.signature})
    end
  end

  @spec decode(binary()) :: {Block.Extrinsic.Disputes.Culprit.t(), binary()}
  def decode(bin) do
    <<work_report_hash::b(hash), key::b(hash), signature::b(signature), rest::binary>> = bin

    {
      %__MODULE__{work_report_hash: work_report_hash, key: key, signature: signature},
      rest
    }
  end

  use JsonDecoder

  def json_mapping, do: %{work_report_hash: :target}
end
