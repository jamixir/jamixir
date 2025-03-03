defmodule Util.Crypto do
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
