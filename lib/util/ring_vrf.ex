defmodule BandersnatchRingVrf do
  use Rustler, otp_app: :jamixir, crate: :bandersnatch_ring_vrf

  # These functions correspond to the NIFs defined in Rust
  def create_ring_context(_file_contents), do: :erlang.nif_error(:nif_not_loaded)
  def create_verifier(_keys), do: :erlang.nif_error(:nif_not_loaded)
  def read_commitment(_commitment), do: :erlang.nif_error(:nif_not_loaded)

  def ring_vrf_verify(_commitment, _vrf_input_data, _aux_data, _signature), do: :erlang.nif_error(:nif_not_loaded)

  def init_ring_context() do
    current_dir = File.cwd!()

    filename =
      Path.join([current_dir, "native/bandersnatch_ring_vrf/data/zcash-srs-2-11-uncompressed.bin"])

    {:ok, file_contents} = File.read(filename)
    # convert from binary to list
    file_contents = :binary.bin_to_list(file_contents)
    create_ring_context(file_contents)
  end
end
