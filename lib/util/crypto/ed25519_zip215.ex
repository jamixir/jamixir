defmodule Util.Crypto.Ed25519Zip215 do
  @moduledoc """
  ZIP215-compliant Ed25519 signature verification.

  This module provides ZIP215-compliant Ed25519 verification using the
  `ed25519-zebra` Rust library via Rustler NIF.

  ## ZIP215 vs RFC8032

  ZIP215 is a consensus-critical variant of Ed25519 that differs from RFC8032:

  1. **Uses cofactor-8 equation**: Verifies 8·[s]B = 8·R + 8·[k]A instead of [s]B = R + [k]A
  2. **Accepts non-canonical point encodings**: Allows y-coordinates ≥ p and non-canonical R
  3. **Requires canonical scalar**: Still requires s < q (same as RFC8032)
  4. **Batch verification safe**: The cofactor equation makes batch verification secure

  ## Why ZIP215?

  ZIP215 is required for JAM Protocol consensus compatibility. The standard library's
  `:crypto.verify/5` uses RFC8032 which rejects valid signatures that other implementations
  accept, causing consensus failures.

  ## Usage

      # Single signature verification
      iex> {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      iex> msg = "Hello, JAM!"
      iex> sig = :crypto.sign(:eddsa, :none, msg, [priv, :ed25519])
      iex> Util.Crypto.Ed25519Zip215.verify(sig, msg, pub)
      :ok

      # Convenience function
      iex> Util.Crypto.Ed25519Zip215.valid_signature?(sig, msg, pub)
      true

      # Batch verification (2-3x faster for multiple signatures)
      iex> items = [
      ...>   {sig1, msg1, pub1},
      ...>   {sig2, msg2, pub2},
      ...>   {sig3, msg3, pub3}
      ...> ]
      iex> Util.Crypto.Ed25519Zip215.batch_verify(items)
      :ok

  ## Performance

  - Single verification: ~100 μs per signature
  - Batch verification: ~40-50 μs per signature (2-3x speedup)

  ## Signing

  **Important**: You don't need to change signing! `:crypto.sign/4` produces canonical
  signatures that work with both RFC8032 and ZIP215 verification. ZIP215 only affects
  the verification rules to accept non-canonical signatures from external sources.

  ## References

  - [ZIP215 Specification](https://zips.z.cash/zip-0215)
  - [ed25519-zebra Documentation](https://docs.rs/ed25519-zebra/)
  - [Why ZIP215?](https://hdevalence.ca/blog/2020-10-04-its-25519am)
  """

  use Rustler, otp_app: :jamixir, crate: "ed25519_zip215"

  @type signature :: binary()
  @type message :: binary()
  @type public_key :: binary()
  @type verify_result ::
          :ok
          | :error
          | :invalid_signature
          | :invalid_public_key
          | :invalid_signature_length
          | :invalid_public_key_length

  @doc """
  Verify an Ed25519 signature using ZIP215 rules.

  ## Parameters

  - `signature` - 64-byte Ed25519 signature
  - `message` - Message that was signed (any length)
  - `public_key` - 32-byte Ed25519 public key

  ## Returns

  - `:ok` - Signature is valid
  - `:error` - Signature is invalid (verification failed)
  - `:invalid_signature_length` - Signature is not 64 bytes
  - `:invalid_public_key_length` - Public key is not 32 bytes
  - `:invalid_signature` - Signature encoding is invalid
  - `:invalid_public_key` - Public key encoding is invalid

  ## Examples

      iex> {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      iex> msg = "test message"
      iex> sig = :crypto.sign(:eddsa, :none, msg, [priv, :ed25519])
      iex> Util.Crypto.Ed25519Zip215.verify(sig, msg, pub)
      :ok

      iex> Util.Crypto.Ed25519Zip215.verify(sig, "wrong message", pub)
      :error

      iex> Util.Crypto.Ed25519Zip215.verify(<<0::512>>, msg, pub)
      :error
  """
  @spec verify(signature(), message(), public_key()) :: verify_result()
  def verify(_signature, _message, _public_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Batch verify multiple Ed25519 signatures using ZIP215 rules.

  Batch verification is 2-3x faster than verifying signatures individually.
  All signatures must be valid for the batch to verify successfully.

  ## Parameters

  - `items` - List of `{signature, message, public_key}` tuples

  ## Returns

  - `:ok` - All signatures are valid
  - `:error` - At least one signature is invalid
  - `:invalid_signature` - At least one signature encoding is invalid
  - `:invalid_public_key` - At least one public key encoding is invalid

  ## Examples

      iex> items = [
      ...>   {sig1, msg1, pub1},
      ...>   {sig2, msg2, pub2},
      ...>   {sig3, msg3, pub3}
      ...> ]
      iex> Util.Crypto.Ed25519Zip215.batch_verify(items)
      :ok

      iex> # Empty list is valid
      iex> Util.Crypto.Ed25519Zip215.batch_verify([])
      :ok

  ## Performance

  Batch verification is particularly beneficial when verifying many signatures:

  - 10 signatures: ~2x speedup
  - 100 signatures: ~2.5x speedup
  - 1000+ signatures: ~3x speedup

  Use cases:
  - Block validation (multiple guarantor signatures)
  - Dispute resolution (multiple judgement signatures)
  - Validator vote aggregation
  """
  @spec batch_verify([{signature(), message(), public_key()}]) :: verify_result()
  def batch_verify(_items) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Check if a signature is valid (convenience function).

  Returns a boolean instead of an atom for easier use in conditional logic.

  ## Parameters

  - `signature` - 64-byte Ed25519 signature
  - `message` - Message that was signed (any length)
  - `public_key` - 32-byte Ed25519 public key

  ## Returns

  - `true` - Signature is valid
  - `false` - Signature is invalid or malformed

  ## Examples

      iex> {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      iex> msg = "test"
      iex> sig = :crypto.sign(:eddsa, :none, msg, [priv, :ed25519])
      iex> Util.Crypto.Ed25519Zip215.valid_signature?(sig, msg, pub)
      true

      iex> Util.Crypto.Ed25519Zip215.valid_signature?(sig, "wrong", pub)
      false
  """
  @spec valid_signature?(signature(), message(), public_key()) :: boolean()
  def valid_signature?(signature, message, public_key) do
    verify(signature, message, public_key) == :ok
  end

  @doc """
  Check if all signatures in a batch are valid (convenience function).

  Returns a boolean instead of an atom for easier use in conditional logic.

  ## Parameters

  - `items` - List of `{signature, message, public_key}` tuples

  ## Returns

  - `true` - All signatures are valid
  - `false` - At least one signature is invalid or malformed

  ## Examples

      iex> items = [{sig1, msg1, pub1}, {sig2, msg2, pub2}]
      iex> Util.Crypto.Ed25519Zip215.valid_batch?(items)
      true

      iex> bad_items = [{sig1, msg1, pub1}, {sig2, "wrong", pub2}]
      iex> Util.Crypto.Ed25519Zip215.valid_batch?(bad_items)
      false
  """
  @spec valid_batch?([{signature(), message(), public_key()}]) :: boolean()
  def valid_batch?(items) do
    batch_verify(items) == :ok
  end
end
