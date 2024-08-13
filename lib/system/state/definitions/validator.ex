defmodule System.State.Validator do
  @moduledoc """
  represent a validator, as specified in section 6.3 of the GP.
  Fomruals 53 -> 57 v0.3.4
  """

  @type t :: %__MODULE__{
          bandersnatch: Types.bandersnatch_key(),
          ed25519: Types.ed25519_key(),
          bls: Types.bls_key(),
          metadata: <<_::1024>>
        }

  defstruct bandersnatch: <<>>, ed25519: <<>>, bls: <<>>, metadata: <<>>
end
