defmodule BandersnatchRingVrf do
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
  def ring_vrf_verify(_commitment, _vrf_input_data, _aux_data, _signature),
    do: :erlang.nif_error(:nif_not_loaded)

  # No explicit formula
  # this is the set of signatures F̄m∈Yr∈YR ⟨x ∈ Y⟩ ⊂ Y784
  def ring_vrf_sign(_ring, _secret, _prover_idx, _vrf_input_data, _aux_data),
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
end
