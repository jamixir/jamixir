defmodule Util.Crypto do
  alias Util.Crypto.Ed25519Zip215
  alias Util.Hash

  def valid_signature?(signature, payload, public_key) do
    Ed25519Zip215.valid_signature?(signature, payload, public_key)
  end

  @spec batch_verify([
          {Ed25519Zip215.signature(), Ed25519Zip215.message(), Ed25519Zip215.public_key()}
        ]) :: Ed25519Zip215.verify_result()
  def batch_verify(items) do
    Ed25519Zip215.batch_verify(items)
  end

  def sign(payload, private_key) do
    :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])
  end

  def create_ed25519_key_pair(seed) do
    secret_seed = Hash.blake2b_256("jam_val_key_ed25519" <> seed)

    :crypto.generate_key(:eddsa, :ed25519, secret_seed)
  end

  def create_bandersnatch_key_pair(seed) do
    seed2 = Hash.blake2b_256("jam_val_key_bandersnatch" <> seed)
    seed3 = :crypto.hash(:sha512, seed2)
    {keypair, _} = RingVrf.generate_secret_from_scalar(seed3 |> :binary.bin_to_list())

    keypair
  end

  use Sizes

  def zero_sign, do: <<0::@signature_size*8>>

  def random_sign do
    :crypto.strong_rand_bytes(@signature_size)
  end
end
