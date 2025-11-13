defmodule Util.Crypto.Ed25519Zip215 do
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

  @spec verify(signature(), message(), public_key()) :: verify_result()
  def verify(_signature, _message, _public_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec batch_verify([{signature(), message(), public_key()}]) :: verify_result()
  def batch_verify(_items) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec valid_signature?(signature(), message(), public_key()) :: boolean()
  def valid_signature?(signature, message, public_key) do
    verify(signature, message, public_key) == :ok
  end

  @spec valid_batch?([{signature(), message(), public_key()}]) :: boolean()
  def valid_batch?(items) do
    batch_verify(items) == :ok
  end
end
