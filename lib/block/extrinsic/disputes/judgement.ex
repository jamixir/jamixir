defmodule Block.Extrinsic.Disputes.Judgement do
  @moduledoc """
  Formula (98) v0.4.1
  essentialy a vote on the validity of a work report.
  """
  alias Util.Crypto

  @type t :: %__MODULE__{
          # i
          validator_index: Types.validator_index(),
          # v
          vote: Types.vote(),
          # s
          signature: Types.ed25519_signature()
        }

  defstruct validator_index: 0, vote: true, signature: Crypto.zero_sign()

  # Formula (100) v0.4.1
  def signature_base(%__MODULE__{vote: vote}) do
    if vote, do: SigningContexts.jam_valid(), else: SigningContexts.jam_invalid()
  end

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Extrinsic.Disputes.Judgement

    def encode(j = %Judgement{}) do
      e({if(j.vote, do: 1, else: 0), e_le(j.validator_index, 2), j.signature})
    end
  end

  use Sizes

  def decode(blob) do
    <<vote::binary-size(1), validator_index::binary-size(@validator_size),
      signature::binary-size(@signature_size), rest::binary>> = blob

    {
      %Block.Extrinsic.Disputes.Judgement{
        validator_index: Codec.Decoder.decode_le(validator_index, @validator_size),
        vote: vote == <<1>>,
        signature: signature
      },
      rest
    }
  end

  use JsonDecoder
  def json_mapping, do: %{validator_index: :index}
end
