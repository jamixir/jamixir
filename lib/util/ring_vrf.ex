defmodule BandersnatchRingVrf do
  use Rustler, otp_app: :jamixir, crate: :bandersnatch_ring_vrf

  def create_verifier(_keys), do: :erlang.nif_error(:nif_not_loaded)

end
