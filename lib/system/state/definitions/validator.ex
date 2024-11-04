defmodule System.State.Validator do
  @moduledoc """
  represent a validator, as specified in section 6.3 of the GP.
  """
  alias System.State.Validator

  # Formula (53) v0.4.5
  @type t :: %__MODULE__{
          # Formula (54) v0.4.5 - b
          bandersnatch: Types.bandersnatch_key(),
          # Formula (55) v0.4.5 - e
          ed25519: Types.ed25519_key(),
          # Formula (56) v0.4.5 - BLS
          bls: Types.bls_key(),
          # Formula (57) v0.4.5 - m
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

  # Formula (59) v0.4.5
  @spec nullify_offenders(
          list(Validator.t()),
          MapSet.t(Types.ed25519_key())
        ) :: list(Validator.t())
  def nullify_offenders([], _), do: []

  def nullify_offenders([%__MODULE__{} | _] = next_validators, offenders) do
    for v <- next_validators, do: if(v.ed25519 in offenders, do: nullified(v), else: v)
  end

  def nullified(validator) do
    %__MODULE__{
      bandersnatch: <<0::size(bit_size(validator.bandersnatch))>>,
      ed25519: <<0::size(bit_size(validator.ed25519))>>,
      bls: <<0::size(bit_size(validator.bls))>>,
      metadata: <<0::size(bit_size(validator.metadata))>>
    }
  end

  use JsonDecoder
end
