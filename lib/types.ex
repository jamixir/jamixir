
defmodule Types do
  @moduledoc """
  A module for defining common types.
  """

  @type hash :: <<_::256>>
  @type ed25519_key :: <<_::256>>
  @type bandersnatch_key :: <<_::256>>
  # 144 bytes
  @type bls_key :: <<_::1152>>
  @type ed25519_signature :: <<_::512>>
  @type validator_index :: integer()
  @type epoch_index :: integer()
  @type decision :: boolean()
end
