defmodule System.Audit do
  # Formula (17.3) v0.6.2
  @spec initial_tranche({binary(), binary()}, binary()) :: binary()
  def initial_tranche(keypair, seal_context) do
    block_seal_output = RingVrf.ietf_vrf_output(keypair, seal_context)

    vrf_context =
      RingVrf.ietf_vrf_output(keypair, SigningContexts.jam_entropy() <> block_seal_output)

    RingVrf.ietf_vrf_sign(keypair, SigningContexts.jam_audit() <> vrf_context, <<>>)
  end

  # Formula (17.5) v0.6.2
  # a0 = { (c,w) ∣ (c,w) ∈ p⋅⋅⋅+10,w ≠ ∅}
  def items_to_audit(p) do
    for {c, w} <- p |> Enum.take(10), w != nil, do: {c, w}
  end

  # Formula (17.6) v0.6.2
  # Formula (17.7) v0.6.2
  # p = F([ (c,Qc) ∣ c <− NC], r)
  def random_selection(keypair, s0, auditable_work_reports) do
    r = RingVrf.ietf_vrf_output(keypair, s0)
    list = for {qc, c} <- Enum.with_index(auditable_work_reports), do: {c, qc}
    Shuffle.shuffle(list, r)
  end
end
