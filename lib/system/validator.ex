defmodule Validator do
  @moduledoc """
  represent a validator, as specified in section 6.3 of the GP.
  """

  @type t :: %__MODULE__{
          bandersnatch: Types.bandersnatch_key(),
          ed25519: Types.ed25519_key(),
          bls: Types.bls_key(),
          metadata: <<_::1024>>
        }

  defstruct bandersnatch: <<>>, ed25519: <<>>, bls: <<>>, metadata: <<>>

  @doc """
  Returns a new Validator struct.
  """
  def new(bandersnatch, ed25519, bls, metadata) do
    %Validator{
      bandersnatch: bandersnatch,
      ed25519: ed25519,
      bls: bls,
      metadata: metadata
    }
  end
end
