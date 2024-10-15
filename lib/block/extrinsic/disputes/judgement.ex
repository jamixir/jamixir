defmodule Block.Extrinsic.Disputes.Judgement do
  @moduledoc """
  Formula (98) v0.4.1
  essentialy a vote on the validity of a work report.
  """
  @type t :: %__MODULE__{
          # i
          validator_index: Types.validator_index(),
          # v
          vote: Types.vote(),
          # s
          signature: Types.ed25519_signature()
        }

  defstruct validator_index: 0, vote: true, signature: <<>>

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

  use JsonDecoder
  def json_mapping, do: %{validator_index: :index}
end
