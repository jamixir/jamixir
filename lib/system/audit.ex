defmodule System.Audit do
  # Formula (17.3) v0.6.6 - s0
  @spec initial_tranche({binary(), binary()}, binary()) :: binary()
  def initial_tranche(keypair, seal_context) do
    block_seal_output = RingVrf.ietf_vrf_output(keypair, seal_context)

    vrf_context =
      RingVrf.ietf_vrf_output(keypair, SigningContexts.jam_entropy() <> block_seal_output)

    RingVrf.ietf_vrf_sign(keypair, SigningContexts.jam_audit() <> vrf_context, <<>>)
  end

  # Formula (17.5) v0.6.6
  # a0 = { (c,w) ∣ (c,w) ∈ p⋅⋅⋅+10,w ≠ ∅}
  def initial_items_to_audit(keypair, s0, auditable_work_reports) do
    p = random_selection(keypair, s0, auditable_work_reports)
    for({c, w} <- p, w != nil, do: {c, w}) |> Enum.take(10)
  end

  # Formula (17.6) v0.6.6
  # Formula (17.7) v0.6.6
  # p = F([ (c,Qc) ∣ c <− NC], r)
  def random_selection(keypair, s0, auditable_work_reports) do
    r = RingVrf.ietf_vrf_output(keypair, s0)
    list = for {qc, c} <- Enum.with_index(auditable_work_reports), do: {c, qc}
    Shuffle.shuffle(list, r)
  end

  # Formula (17.8) v0.6.6
  @spec current_trench(Types.timeslot(), Types.timeslot()) :: non_neg_integer()
  def current_trench(header_t, state_t) do
    div(state_t - Constants.slot_period() * header_t, Constants.audit_trenches_period())
  end

  alias Util.Crypto
  import Codec.Encoder
  # Formula (17.10) v0.6.6
  # xn = E([E2(c)⌢H(w) ∣ (c,w) ∈ an])
  def encoded_announcements(n) do
    an = announcements(n)
    e(for {c, w} <- an, do: <<c::16-little>> <> h(w))
  end

  # Formula (17.9) v0.6.6
  def announcements_signature(private_key, header, n) do
    Crypto.sign(sign_payload(header, n), private_key)
  end

  def sign_payload(header, n) do
    xn = encoded_announcements(n)
    SigningContexts.jam_announce() <> n <> xn <> h(e(header))
  end

  # Formula (17.16) v0.6.6
  def announcements(_n) do
    # TODO
    []
  end
end
