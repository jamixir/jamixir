defmodule Block.Extrinsic.Disputes.Judgement do
  @moduledoc """
  Formula (98) v0.4.5
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

  # Formula (100) v0.4.5
  def signature_base(%__MODULE__{vote: vote}) do
    if vote, do: SigningContexts.jam_valid(), else: SigningContexts.jam_invalid()
  end

  defimpl Encodable do
    use Codec.Encoder
    use Sizes

    def encode(j = %Block.Extrinsic.Disputes.Judgement{}) do
      e({if(j.vote, do: 1, else: 0), e_le(j.validator_index, @validator_index_size), j.signature})
    end
  end

  use Sizes
  use Codec.Decoder

  @spec decode(binary()) :: {Block.Extrinsic.Disputes.Judgement.t(), binary()}
  def decode(bin) do
    <<vote::binary-size(1), validator_index::binary-size(@validator_index_size),
      signature::binary-size(@signature_size), rest::binary>> = bin

    {
      %__MODULE__{
        validator_index: de_le(validator_index, @validator_index_size),
        vote: vote == <<1>>,
        signature: signature
      },
      rest
    }
  end

  def size do
    @validator_index_size + 1 + @signature_size
  end

  use JsonDecoder
  @spec json_mapping() :: %{validator_index: :index}
  def json_mapping, do: %{validator_index: :index}
end
