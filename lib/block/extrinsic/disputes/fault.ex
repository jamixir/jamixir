defmodule Block.Extrinsic.Disputes.Fault do
  @moduledoc """
  Formula (98) v0.4.1
  Faults represent validators who have signed  a judgement that was found to be in
  cotradiction with the work-report's validity.
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

    def encode(f = %Fault{}) do
      dec = if f.vote, do: 1, else: 0
      e({f.work_report_hash, dec, f.key, f.signature})
    end
  end

  use Sizes

  @spec decode(binary()) :: {Block.Extrinsic.Disputes.Fault.t(), binary()}
  def decode(blob) do
    <<work_report_hash::binary-size(@hash_size), vote::binary-size(1),
      key::binary-size(@hash_size), signature::binary-size(@signature_size), rest::binary>> = blob

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
