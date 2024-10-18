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
  def valid_signature?(signature, payload, public_key) do
    :crypto.verify(:eddsa, :none, payload, signature, [public_key, :ed25519])
  end

  def sign(payload, private_key) do
    :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])
  end

  use Sizes

  def zero_sign do
    Utils.zero_bitstring(@signature_size)
  end

  def random_sign do
    :crypto.strong_rand_bytes(@signature_size)
  end
end
