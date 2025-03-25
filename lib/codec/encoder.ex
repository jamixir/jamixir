defmodule Codec.Encoder do
  alias Codec.NilDiscriminator
  alias Codec.VariableSize
  alias Util.Hash

  @spec encode(any()) :: binary()
  def encode(value) do
    do_encode(value)
  end

  # Formula (C.5) v.0.5.0
  @spec encode_little_endian(integer(), integer()) :: binary()
  def encode_little_endian(_, 0), do: <<>>

  def encode_little_endian(x, l), do: <<x::l*8-little>>

  @spec encode_le(integer(), integer()) :: binary()
  def encode_le(x, l), do: encode_little_endian(x, l)

  # Formula (E.9) v0.6.0
  # b ↦ E(↕[¿x ∣ x <− b])
  @spec encode_mmr(list(Types.hash() | nil)) :: Types.hash()
  def encode_mmr(mmr) do
    do_encode(VariableSize.new(for b <- mmr, do: NilDiscriminator.new(b)))
  end

  use Sizes

  # Formula (E.10) v0.6.0
  def super_peak_mmr(b) do
    case for h <- b, h != nil, do: h do
      [] ->
        Hash.zero()

      [h0] ->
        h0

      h ->
        {init, [last]} = Enum.split(h, -1)
        Hash.keccak_256("peak" <> super_peak_mmr(init) <> last)
    end
  end

  # Private Functions

  defp bit_list?([]), do: true
  defp bit_list?([0 | rest]), do: bit_list?(rest)
  defp bit_list?([1 | rest]), do: bit_list?(rest)
  defp bit_list?(_), do: false

  # Formula (C.1) v.0.5.0
  defp do_encode(nil), do: <<>>
  # Formula (C.2) v.0.5.0
  defp do_encode(value) when is_binary(value) or is_bitstring(value), do: value
  # Formula (C.3) v.0.5.0
  defp do_encode(value) when is_tuple(value), do: value |> Tuple.to_list() |> encode_list()

  # Formula (C.7) v.0.5.0
  defp do_encode(value) when is_list(value) do
    if bit_list?(value) do
      encode_bits(value)
    else
      encode_list(value)
    end
  end

  # Formula (C.11) v.0.5.0
  defp do_encode(%MapSet{} = m), do: MapSet.to_list(m) |> do_encode()

  defp do_encode(value) when is_struct(value) do
    if encodable?(value) do
      Encodable.encode(value)
    else
      raise "Struct does not implement Encodable protocol"
    end
  end

  # Formula (C.11) v.0.5.0
  defp do_encode(value) when is_map(value) and not is_struct(value) do
    encoded_pairs =
      for {k, v} <- Enum.sort_by(value, fn {k, _v} -> k end), do: {encode(k), encode(v)}

    encode(VariableSize.new(encoded_pairs))
  end

  defp do_encode(value) when is_integer(value), do: encode_integer(value)

  defp encodable?(data) do
    not is_nil(Encodable.impl_for(data))
  end

  # l = 0 => 2 < x < 2^7
  # l = 1 => 2^7 <= x < 2^14
  # l = 2 => 2^14 <= x < 2^21
  # ...
  # l = 7 => 2^49 <= x < 2^56
  # Formula (C.6) v.0.5.0
  defp exists_l_in_n8(x) do
    l = trunc(:math.log2(x) / 7)

    if l in 0..7 do
      l
    else
      nil
    end
  end

  # Formula (C.6) v.0.5.0
  defp encode_integer(0), do: <<0>>

  # Formula (C.6) v.0.5.0
  defp encode_integer(x) do
    if x >= 2 ** 64, do: raise(ArgumentError, "Integer value is too large to encode")

    case exists_l_in_n8(x) do
      nil -> <<2 ** 8 - 1>> <> encode_le(x, 8)
      l -> <<2 ** 8 - 2 ** (8 - l) + div(x, 2 ** (8 * l))>> <> encode_le(rem(x, 2 ** (8 * l)), l)
    end
  end

  defp encode_list(value) do
    Enum.map_join(value, &do_encode/1)
  end

  # Formula (C.10) v.0.5.0
  defp encode_bits([]), do: <<>>

  defp encode_bits(bits) do
    {chunk, rest} = Enum.split(bits, 8)

    <<encode_octet(chunk)>> <> encode_bits(rest)
  end

  defp encode_octet(bits) do
    bits
    |> Enum.with_index()
    |> Enum.reduce(0, fn {bit, i}, acc -> acc + bit * 2 ** i end)
  end

  defmacro __using__(_) do
    quote do
      alias Codec.VariableSize
      import Codec.Encoder
      def e(value), do: Codec.Encoder.encode(value)
      def e_le(value, l), do: Codec.Encoder.encode_le(value, l)
      def vs(value), do: VariableSize.new(value)
      def h(value), do: Hash.default(value)
    end
  end

  use Sizes

  def binary_registry do
    %{
      # Use byte size * 8 for binary types
      hash: @hash_size,
      signature: @signature_size,
      ed25519_key: @hash_size,
      ed25519_signature: @signature_size,
      bandersnatch_key: @hash_size,
      bandersnatch_signature: Sizes.bandersnatch_signature(),
      bandersnatch_proof: @bandersnatch_proof_size,
      export_segment: Sizes.export_segment(),
      erasure_coded_piece: Sizes.erasure_coded_piece(),
      bitfield: Sizes.bitfield(),
      merkle_root: Sizes.merkle_root(),

      # Use byte size plus endianness for integer types
      validator_index: {16, :little},
      core_index: {16, :little},
      epoch: {32, :little},
      epoch_index: {32, :little},
      timeslot: {32, :little},
      service_index: {32, :little},
      service_id: {32, :little},
      service: {32, :little},
      balance: {64, :little},
      gas: {64, :little},
      gas_result: {64, :little},
      gas_ratio: {64, :little},
      register: {64, :little},
      max_age_timeslot_lookup_anchor: {32, :little}
    }
  end

  defmacro m(var) do
    var_name =
      case var do
        {{:., _, [{_, _, _}, name]}, _, []} when is_atom(name) -> name
        {name, _, _} -> name
        name when is_atom(name) -> name
      end

    case Map.get(binary_registry(), var_name) do
      nil -> var
      {size, :little} -> quote(do: unquote(size) - little)
      size -> quote(do: unquote(size) * 8)
    end
  end

  defmacro b(var) do
    quote do
      binary - m(unquote(var))
    end
  end

  defmacro t(var) do
    quote do
      <<unquote(var)::m(unquote(var))>>
    end
  end

  defmacro hash do
    quote do
      m(hash)
    end
  end

  defmacro service do
    quote do
      m(service)
    end
  end
end
