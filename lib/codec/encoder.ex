defmodule Codec.Encoder do
  alias Codec.NilDiscriminator
  alias Codec.VariableSize
  alias Util.Hash

  @type encoding_type ::
          :timeslot
          | :service_index
          | :balance
          | :gas
          | :binary
          | :account_octets
          | :account_items
          | :core_index
          | :delegate
          | nil

  # Byte sizes
  @type_sizes %{
    timeslot: 4,
    service_index: 4,
    balance: 8,
    gas: 8,
    account_octets: 8,
    account_items: 4,
    core_index: 2
  }

  @spec encode_typed(list(), list(encoding_type())) :: binary()
  def encode_typed(values, types \\ []) when is_list(values) do
    values
    |> Stream.with_index()
    |> Stream.map(fn {value, index} ->
      type = if index < length(types), do: Enum.at(types, index), else: nil
      encode_with_type(value, type)
    end)
    |> Enum.join()
  end

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

  defp encode_with_type(value, nil), do: do_encode(value)
  defp encode_with_type(value, :delegate), do: do_encode(value)
  defp encode_with_type(value, :binary), do: value

  defp encode_with_type(value, type) when is_map_key(@type_sizes, type),
    do: encode_little_endian(value, @type_sizes[type])

  defp encode_with_type(value, _), do: do_encode(value)

  defmacro __using__(_) do
    quote do
      alias Codec.VariableSize
      def e(value), do: Codec.Encoder.encode(value)
      def e(values, types), do: Codec.Encoder.encode_typed(values, types)
      def e_le(value, l), do: Codec.Encoder.encode_le(value, l)
      def vs(value), do: VariableSize.new(value)
      def h(value), do: Hash.default(value)
    end
  end
end
