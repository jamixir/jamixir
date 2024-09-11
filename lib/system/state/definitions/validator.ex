defmodule System.State.Validator do
  @moduledoc """
  represent a validator, as specified in section 6.3 of the GP.
  """

  # Formula (53) v0.3.4
  @type t :: %__MODULE__{
          # Formula (54) v0.3.4
          bandersnatch: Types.bandersnatch_key(),
          # Formula (55) v0.3.4
          ed25519: Types.ed25519_key(),
          # Formula (56) v0.3.4
          bls: Types.bls_key(),
          # Formula (57) v0.3.4
          metadata: <<_::1024>>
        }

  defstruct bandersnatch: <<>>, ed25519: <<>>, bls: <<>>, metadata: <<>>

  def key(v), do: v.bandersnatch <> v.ed25519 <> v.bls <> v.metadata

  defimpl Encodable do
    alias System.State.Validator

    def encode(%Validator{} = v) do
      Validator.key(v)
    end
  end

  def from_json(json) do
    struct(%__MODULE__{}, Utils.hex_to_binary(json))
  end
end
