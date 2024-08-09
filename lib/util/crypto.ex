defmodule Util.Crypto do
  @moduledoc """
  Utility module for cryptographic operations.
  """

  @doc """
  Verifies an Ed25519 signature.

  ## Parameters
  - `signature`: The signature to verify.
  - `payload`: The original message that was signed.
  - `public_key`: The public key corresponding to the private key that signed the message.

  ## Returns
  - `true` if the signature is valid.
  - `false` otherwise.
  """
  def verify_signature(signature, payload, public_key) do
    :crypto.verify(:eddsa, :none, payload, signature, [public_key, :ed25519])
  end

  def entropy_vrf(value) do
    # TODO

    # for now, we will just return the value
    value
  end
end
