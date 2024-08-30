defmodule RingVrf do
  use Rustler, otp_app: :jamixir, crate: :bandersnatch_ring_vrf

  # load static ring context data from a file
  # following the example https://github.com/davxy/bandersnatch-vrfs-spec/blob/main/example/src/main.rs
  def create_ring_context(_filename, _ring_size), do: :erlang.nif_error(:nif_not_loaded)
  def init_ring_context(ring_size) do
    current_dir = File.cwd!()

    filename =
      Path.join([current_dir, "native/bandersnatch_ring_vrf/data/zcash-srs-2-11-uncompressed.bin"])

    create_ring_context(filename, ring_size)
  end

  # Formula (311) v0.3.4
  @spec create_commitment(any()) :: any()
  def create_commitment(_keys), do: :erlang.nif_error(:nif_not_loaded)

  # Formula (312) v0.3.4
  # Formula (313) v0.3.4
  def ring_vrf_verify(_commitment, _context, _message, _signature),
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
  def generate_secret_from_rand() do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Generate a secret from a scalar
  def generate_secret_from_scalar(_scalar_bytes) do
    :erlang.nif_error(:nif_not_loaded)
  end

  # IETF VRF Sign
  # Non-Anonymous VRF signature
  # Used for ticket claiming during block production
  # Formula (309) v0.3.4
  # Formula (310) v0.3.4
  def ietf_vrf_sign(_secret, _context, _message),
    do: :erlang.nif_error(:nif_not_loaded)

  # IETF VRF Verify
  #  Non-Anonymous VRF signature verification.
  #  Used for ticket claim verification during block import.
  #  Not used with Safrole test vectors.
  def ietf_vrf_verify(_ring, _context, _message, _signature, _signer_key_index),
    do: :erlang.nif_error(:nif_not_loaded)
end
