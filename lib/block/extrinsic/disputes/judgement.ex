defmodule Block.Extrinsic.Disputes.Judgement do
  use Sizes
  import Codec.Encoder, only: [m: 1]

  @moduledoc """
  Formula (10.2) v0.6.6
  """
  @type t :: %__MODULE__{
          # v
          vote: Types.vote(),
          # i
          validator_index: Types.validator_index(),
          # s
          signature: Types.ed25519_signature()
        }

  defstruct [:vote, :validator_index, :signature]

  # Formula (10.4) v0.6.6
  def signature_base(%__MODULE__{vote: vote}) do
    if vote, do: SigningContexts.jam_valid(), else: SigningContexts.jam_invalid()
  end

  defimpl Encodable do
    import Codec.Encoder, only: [e: 1, t: 1, m: 1]
    use Sizes

    def encode(%Block.Extrinsic.Disputes.Judgement{} = j) do
      e({if(j.vote, do: 1, else: 0), t(j.validator_index), j.signature})
    end
  end

  @spec decode(binary()) :: {Block.Extrinsic.Disputes.Judgement.t(), binary()}
  def decode(bin) do
    <<vote::binary-size(1), validator_index::m(validator_index),
      signature::binary-size(@signature_size), rest::binary>> = bin

    {
      %__MODULE__{
        validator_index: validator_index,
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
