defmodule Codec.State.Trie do
  alias System.State
  alias Util.Hash

  alias System.State.{
    CoreReport,
    EntropyPool,
    Judgements,
    PrivilegedServices,
    Ready,
    RecentHistory,
    Safrole,
    ServiceAccount,
    Validator,
    ValidatorStatistics
  }

  alias Util.{Hex, Merklization}
  alias Codec.{NilDiscriminator, VariableSize}
  import Codec.{Encoder, Decoder}

  import Bitwise

  defmodule SerializedState do
    defstruct [:data]
  end

  @storage_prefix (1 <<< 32) - 1
  @preimage_prefix (1 <<< 32) - 2

  # Formula (D.2) v0.6.7
  def state_keys(%State{} = s) do
    %{
      # C(1) ↦ E([↕x ∣ x <− α])
      1 => e(Enum.map(s.authorizer_pool, &vs/1)),
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
      10 => e(Enum.map(s.core_reports, &NilDiscriminator.new/1)),
      # C(11) ↦ E4(τ)
      11 => t(s.timeslot),
      # C(12) ↦ E4(χ)
      12 => e(s.privileged_services),
      # C(13) ↦ E4(π)
      13 => e(s.validator_statistics),
      14 => e(Enum.map(s.ready_to_accumulate, &vs/1)),
      15 => e(Enum.map(s.accumulation_history, &vs/1)),
      16 => e(vs(for {s, h} <- s.accumulation_outputs, do: {<<s::m(service), h::b(hash)>>}))
    }
    |> encode_accounts(s)
    |> encode_accounts_storage_s(s)
    |> encode_accounts_storage_p(s, :preimage_storage_p)
    |> encode_accounts_preimage_storage_l(s)
  end

  # Formula (D.1) v0.6.7 - C constructor
  # (i, s ∈ NS) ↦ [i, n0, 0, n1, 0, n2, 0, n3, 0, 0, . . . ] where n = E4(s)
  def key_to_31_octet({i, s}) when i < 256 and s < 4_294_967_296 do
    <<n0, n1, n2, n3>> = e_le(s, 4)
    <<i::8>> <> <<n0, 0, n1, 0, n2, 0, n3, 0>> <> <<0::176>>
  end

  # (s, h) ↦ [n0, h0, n1, h1, n2, h2, n3, h3, h4, h5, . . . , h27] where
  def key_to_31_octet({s, h}) do
    <<n0, n1, n2, n3>> = e_le(s, 4)
    <<a_part::binary-size(27), _rest::binary>> = Hash.default(h)
    <<a0, a1, a2, a3, rest::binary>> = a_part
    <<n0, a0, n1, a1, n2, a2, n3, a3>> <> rest
  end

  # i ∈ N2^8 ↦ [i, 0, 0, . . . ]
  def key_to_31_octet(key) when key < 256, do: <<key::8, 0::240>>

  def octet31_to_key(<<key::8, 0::240>>) when key < 255, do: key

  def octet31_to_key(<<i::8, n0, 0, n1, 0, n2, 0, n3, 0, 0::176>>) do
    s = de_le(<<n0, n1, n2, n3>>, 4)
    {i, s}
  end

  def octet31_to_key(<<n0, h0, n1, h1, n2, h2, n3, h3, rest::binary-size(23)>>) do
    s = de_le(<<n0, n1, n2, n3>>, 4)
    h = <<h0, h1, h2, h3>> <> rest
    {s, h}
  end

  def serialize(state) do
    serialized = for({k, v} <- state_keys(state), do: {key_to_31_octet(k), v}, into: %{})
    %SerializedState{data: serialized}
  end

  def serialize_hex(state, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, false)

    for {k, v} <- serialize(state) |> Map.get(:data),
        do: {Hex.encode16(k, prefix: prefix), Hex.encode16(v, prefix: prefix)},
        into: %{}
  end

  def from_json(json) do
    for item <- json, into: %{} do
      dict = JsonDecoder.from_json(item)

      {dict[:key], dict[:value]}
    end
  end

  def state_root(%State{} = state), do: state_root(serialize(state))

  def state_root(%SerializedState{} = serialized_state),
    do: Merklization.merkelize_state(serialized_state)

  def to_binary(%State{} = state), do: to_binary(serialize(state))

  def to_binary(%SerializedState{data: data}) do
    key_value_list =
      for {key, value} <- data do
        # TrieKey ::= OCTET STRING (SIZE(31))
        # value   OCTET STRING  (SEQUENCE of u8) [includes length prefix]
        key <> e(vs(value))
      end

    # State ::= SEQUENCE OF KeyValue [includes length prefix]
    e(vs(key_value_list))
  end

  @spec from_binary(nonempty_binary()) ::
          {:ok, %SerializedState{data: map()}, binary()} | {:error, :invalid_state_format}
  def from_binary(binary) do
    try do
      # State ::= SEQUENCE OF KeyValue [includes length prefix]
      {key_value_list, rest} =
        VariableSize.decode(binary, fn bin ->
          #   KeyValue ::= SEQUENCE {
          #     key     TrieKey ::= OCTET STRING (SIZE(31)),
          #     value   OCTET STRING (SEQUENCE of u8) [includes length prefix]
          # }

          # TrieKey
          <<key::binary-size(31), rest::binary>> = bin
          # value
          {value, rest} = VariableSize.decode(rest, :binary)
          {{key, value}, rest}
        end)

      data = Map.new(key_value_list)
      {:ok, %SerializedState{data: data}, rest}
    rescue
      MatchError -> {:error, :invalid_state_format}
    end
  end

  def deserialize(%SerializedState{data: data}), do: trie_to_state(data)

  # ∀(s ↦ a) ∈ δ ∶ C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
  defp encode_accounts(%{} = state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {id, service}, ac ->
      Map.put(ac, {255, id}, e(service))
    end)
  end

  # ∀(s ↦ a) ∈ δ,(k ↦ v) ∈ as ∶ C(s,E4(2^32−1) ⌢ k) ↦ v
  defp encode_accounts_storage_s(state_keys, %State{} = state) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      a.storage.original_map
      |> Enum.reduce(ac, fn {h, v}, ac ->
        Map.put(ac, {s, e_le(@storage_prefix, 4) <> h}, v)
      end)
    end)
  end

  # ∀(s ↦ a) ∈ δ,(h ↦ p) ∈ ap ∶ C(s,E4(2^32−2) ⌢ h) ↦ p
  defp encode_accounts_storage_p(state_keys, %State{} = state, property) do
    state.services
    |> Enum.reduce(state_keys, fn {s, a}, ac ->
      Map.get(a, property)
      |> Enum.reduce(ac, fn {h, v}, ac ->
        Map.put(ac, {s, e_le(@preimage_prefix, 4) <> h}, v)
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
        key = e_le(l, 4) <> h
        Map.put(ac, {s, key}, value)
      end)
    end)
  end

  def trie_to_state(%SerializedState{data: trie}), do: trie_to_state(trie)

  def trie_to_state(trie) do
    dict =
      for {k, v} <- trie, into: %{} do
        id = octet31_to_key(k)
        value = decode_value(id, v)
        {id, elem(value, 0)}
      end

    services =
      for {{255, service_id}, v} <- dict, reduce: %{} do
        acc ->
          # storage keys can't be recovered
          storage = HashedKeysMap.new(%{})

          preimage_storage_p =
            for {{^service_id, bin_key}, v} <- dict,
                recovered_key =
                  key_to_31_octet({service_id, <<@preimage_prefix::little-32>> <> h(v)}),
                recovered_key |> binary_slice(8, 20) == bin_key |> binary_slice(4, 20),
                into: %{} do
              {Hash.default(v), v}
            end

          preimage_storage_l =
            for {h, p} <- preimage_storage_p, into: %{} do
              l = byte_size(p)
              trie_key = key_to_31_octet({service_id, e_le(l, 4) <> h})

              value =
                VariableSize.decode(trie[trie_key], fn <<x::little-32, rest::binary>> ->
                  {x, rest}
                end)
                |> elem(0)

              {{h, l}, p}
              {{h, l}, value}
            end

          Map.put(acc, service_id, %ServiceAccount{
            v
            | storage: storage,
              preimage_storage_p: preimage_storage_p,
              preimage_storage_l: preimage_storage_l
          })
      end

    %State{
      authorizer_pool: dict[1],
      authorizer_queue: dict[2],
      recent_history: dict[3],
      safrole: dict[4],
      judgements: dict[5],
      entropy_pool: dict[6],
      next_validators: dict[7],
      curr_validators: dict[8],
      prev_validators: dict[9],
      core_reports: dict[10],
      timeslot: dict[11],
      privileged_services: dict[12],
      validator_statistics: dict[13],
      ready_to_accumulate: dict[14],
      accumulation_history: dict[15],
      services: services
    }
  end

  # authorizer_pool
  def decode_value(1, v),
    do: decode_list(v, Constants.core_count(), &VariableSize.decode(&1, :hash))

  # authorizer_queue
  def decode_value(2, v),
    do:
      decode_list(
        v,
        Constants.core_count(),
        &decode_list(&1, :hash, Constants.max_authorization_queue_items())
      )

  def decode_value(3, v), do: RecentHistory.decode(v)
  def decode_value(4, v), do: Safrole.decode(v)
  def decode_value(5, v), do: Judgements.decode(v)
  def decode_value(6, v), do: EntropyPool.decode(v)
  def decode_value(7, v), do: decode_list(v, Constants.validator_count(), Validator)
  def decode_value(8, v), do: decode_list(v, Constants.validator_count(), Validator)
  def decode_value(9, v), do: decode_list(v, Constants.validator_count(), Validator)

  def decode_value(10, v),
    do:
      decode_list(v, Constants.core_count(), fn c ->
        NilDiscriminator.decode(c, &CoreReport.decode/1)
      end)

  def decode_value(11, value), do: {de_le(value, 4), <<>>}
  def decode_value(12, value), do: PrivilegedServices.decode(value)
  def decode_value(13, value), do: ValidatorStatistics.decode(value)

  def decode_value(14, value),
    do: decode_list(value, Constants.epoch_length(), &VariableSize.decode(&1, Ready))

  # accumulation_history
  def decode_value(15, value) do
    decode_list(value, Constants.epoch_length(), &VariableSize.decode(&1, :mapset, 32))
  end

  def decode_value({255, _service_id}, bin) do
    ServiceAccount.decode(bin)
  end

  # storage item / preimage_storage_s and preimage_storage_l
  def decode_value({_service_id, _key}, bin),
    do: {bin, <<>>}

  def decode_value(_key, _value) do
    {nil, <<>>}
  end
end
