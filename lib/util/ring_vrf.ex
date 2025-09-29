defmodule RingVrf do
  use Rustler, otp_app: :jamixir, crate: :bandersnatch_ring_vrf
  use Memoize
  alias Util.Logger
  # load static ring context data from a file
  # following the example https://github.com/davxy/bandersnatch-vrfs-spec/blob/main/example/src/main.rs
  def create_ring_context(_ring_size), do: :erlang.nif_error(:nif_not_loaded)

  def init_ring_context, do: init_ring_context(Constants.validator_count())

  defmemo init_ring_context(ring_size) do
    Logger.info("💍 Initializing ring context with size #{ring_size}")
    create_ring_context(ring_size)
  end

  # Formula (G.3) v0.7.2
  @spec cached_commitment(any()) :: any()
  defmemo cached_commitment(keys) do
    create_commitment(keys)
  end

  @spec create_commitment(any()) :: any()
  def create_commitment(_keys), do: :erlang.nif_error(:nif_not_loaded)

  # Formula (G.4) v0.7.2
  # Formula (G.5) v0.7.2
  defmemo ring_vrf_verify(commitment, context, message, signature) do
    ring_vrf_verify_impl(commitment, context, message, signature)
  end

  defp ring_vrf_verify_impl(_commitment, _context, _message, _signature),
    do: :erlang.nif_error(:nif_not_loaded)

  # No explicit formula
  # this is the set of signatures F̄m∈Yr∈YR ⟨x ∈ Y⟩ ⊂ Y784
  def ring_vrf_sign(_ring, _secret, _prover_idx, _context, _message),
    do: :erlang.nif_error(:nif_not_loaded)

  # Function to handle (secret, public_key) pair generation
  # Generate a secret from a seed
  # not explictly mentioned in the paper - but mentioned in https://eprint.iacr.org/2023/002
  # and of course, we cannot sign and verify without creating secret/public key pairs
  def generate_secret_from_seed(_seed) do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Generate a secret using randomness
  def generate_secret_from_rand do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Generate a secret from a scalar
  def generate_secret_from_scalar(_scalar_bytes) do
    :erlang.nif_error(:nif_not_loaded)
  end

  # IETF VRF Sign
  # Non-Anonymous VRF signature
  # Used for ticket claiming during block production
  # Formula (G.1) v0.7.2
  # Formula (G.2) v0.7.2
  def ietf_vrf_sign(_keypair, _context, _message),
    do: :erlang.nif_error(:nif_not_loaded)

  # IETF VRF Verify
  #  Non-Anonymous VRF signature verification.
  #  Used for ticket claim verification during block import.
  #  Not used with Safrole test vectors.
  def ietf_vrf_verify(_key, _context, _message, _signature),
    do: :erlang.nif_error(:nif_not_loaded)

  def ietf_vrf_output(secret, context), do: ietf_vrf_sign(secret, context, <<>>) |> elem(1)

  def ring_vrf_output(ring, secret, prover_idx, context),
    do: ring_vrf_sign(ring, secret, prover_idx, context, <<>>) |> elem(1)
end
