defmodule Block.Extrinsic.Disputes.Fault do
  @moduledoc """
  Formula (10.2) v0.6.2
  """
  alias Types

  @type t :: %__MODULE__{
          # r
          work_report_hash: Types.hash(),
          # v
          vote: Types.vote(),
          # k
          key: Types.ed25519_key(),
          # s
          signature: Types.ed25519_signature()
        }

  defstruct work_report_hash: <<>>, vote: true, key: <<>>, signature: <<>>

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Extrinsic.Disputes.Fault

    def encode(%Fault{} = f) do
      dec = if f.vote, do: 1, else: 0
      e({f.work_report_hash, dec, f.key, f.signature})
    end
  end

  use Codec.Encoder

  @spec decode(binary()) :: {Block.Extrinsic.Disputes.Fault.t(), binary()}
  def decode(bin) do
    <<work_report_hash::b(hash), vote::binary-size(1), key::b(hash), signature::b(signature),
      rest::binary>> = bin

    {
      %__MODULE__{
        work_report_hash: work_report_hash,
        vote: vote == <<1>>,
        key: key,
        signature: signature
      },
      rest
    }
  end

  use JsonDecoder
  def json_mapping, do: %{work_report_hash: :target}
end
