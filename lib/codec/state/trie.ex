defmodule Codec.State.Trie do
  alias Util.Merklization
  alias System.State
  alias Codec.NilDiscriminator
  alias Util.{Hash, Hex}
  use Codec.Encoder
  import Bitwise

  # # Formula (D.2) v0.5
  def state_keys(%State{} = s) do
    %{
      # C(1) ↦ E([↕x ∣ x <− α])
      1 => e(for x <- s.authorizer_pool, do: vs(x)),
      # C(2) ↦ E(φ)
      2 => e(s.authorizer_queue),
      # C(3) ↦ E(↕[(h, EM (b), s, ↕p) ∣ (h, b, s, p) <− β])
      3 => e(s.recent_history),
      # C(4) - safrole encoding
      4 => e(s.safrole),
      # C(5) ↦ judgements encoding
      5 => e(s.judgements),
      # C(6) ↦ E(η)
      6 => e(s.entropy_pool),
      # C(7) ↦ E(ι)
      7 => e(s.next_validators),
      # C(8) ↦ E(κ)
      8 => e(s.curr_validators),
      # C(9) ↦ E(λ)
      9 => e(s.prev_validators),
      # C(10) ↦ E([¿(w, E4(t)) ∣ (w, t) <− ρ])
      10 => e(for c <- s.core_reports, do: NilDiscriminator.new(c)),
      # C(11) ↦ E4(τ)
      11 => e_le(s.timeslot, 4),
      # C(12) ↦ E4(χ)
      12 => e(s.privileged_services),
      # C(13) ↦ E4(π)
      13 => e(s.validator_statistics),
      14 => e(for x <- s.accumulation_history, do: vs(x)),
      15 => e(for x <- s.ready_to_accumulate, do: vs(x))
    }
    |> encode_accounts(s)
    |> encode_accounts_storage_s(s, :storage)
    |> encode_accounts_storage_p(s, :preimage_storage_p)
    |> encode_accounts_preimage_storage_l(s)
  end

  # Formula (D.1) v0.5 - C constructor
  # (i, s ∈ NS) ↦ [i, n0, 0, n1, 0, n2, 0, n3, 0, 0, . . . ] where n = E4(s)
  def key_to_32_octet({i, s}) when i < 256 and s < 4_294_967_296 do
    <<n0, n1, n2, n3>> = e_le(s, 4)
    <<i::8>> <> <<n0, 0, n1, 0, n2, 0, n3, 0>> <> <<0::184>>
  end

  # (s, h) ↦ [n0, h0, n1, h1, n2, h2, n3, h3, h4, h5, . . . , h27] where
  def key_to_32_octet({s, h}) do
    <<n0, n1, n2, n3>> = e_le(s, 4)
    <<h_part::binary-size(28), _rest::binary>> = h
    <<h0, h1, h2, h3, rest::binary>> = h_part
    <<n0, h0, n1, h1, n2, h2, n3, h3>> <> rest
  end

  # i ∈ N2^8 ↦ [i, 0, 0, . . . ]
  def key_to_32_octet(key) when key < 256, do: <<key::8, 0::248>>

  def serialize(state) do
    for({k, v} <- state_keys(state), do: {key_to_32_octet(k), v}, into: %{})
  end

  def serialize_hex(state, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, false)

    for {k, v} <- serialize(state),
        do: {Hex.encode16(k, prefix: prefix), Hex.encode16(v, prefix: prefix)},
        into: %{}
  end

  def state_root(state), do: Merklization.merkelize_state(serialize(state))

  # ∀(s ↦ a) ∈ δ ∶ C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
  defp encode_accounts(%{} = state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {id, service}, ac ->
      Map.put(ac, {255, id}, e(service))
    end)
  end

  # ∀(s ↦ a) ∈ δ, (k ↦ v) ∈ as ∶ C(s, E4 (2^32 − 1) ⌢ k0...28 ) ↦ v
  defp encode_accounts_storage_s(state_keys, %State{} = state, property) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      Map.get(a, property)
      |> Enum.reduce(ac, fn {h, v}, ac ->
        Map.put(ac, {s, e_le((1 <<< 32) - 1, 4) <> binary_slice(h, 0, 28)}, v)
      end)
    end)
  end

  # ∀(s ↦ a) ∈ δ, (h ↦ p) ∈ ap ∶ C(s, E4 (2^32 − 2) ⌢ h1...29 ) ↦ p
  defp encode_accounts_storage_p(state_keys, %State{} = state, property) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      Map.get(a, property)
      |> Enum.reduce(ac, fn {h, v}, ac ->
        Map.put(ac, {s, e_le((1 <<< 32) - 2, 4) <> binary_slice(h, 1, 28)}, v)
      end)
    end)
  end

  # ∀(s ↦ a) ∈ δ, ((h, l) ↦ t) ∈ al ∶ C(s, E4 (l) ⌢ H(h)2...30 ) ↦ E(↕[E4 (x) ∣ x −< t])
  defp encode_accounts_preimage_storage_l(state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      a.preimage_storage_l
      |> Enum.reduce(ac, fn {{h, l}, t}, ac ->
        value = e(vs(for x <- t, do: e_le(x, 4)))
        key = (e_le(l, 4) <> Hash.default(h)) |> binary_slice(2, 28)
        Map.put(ac, {s, key}, value)
      end)
    end)
  end
end
