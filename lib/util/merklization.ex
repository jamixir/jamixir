defmodule Util.Merklization do
  @moduledoc """
  Apendix D. STATE MERKLIZATION
  D.2. Merklization
  D.2.1. Node Encoding and Trie Identification

  """
  use Memoize

  alias Util.Hash
  import Codec.Encoder
  alias Codec.State.Trie.SerializedState

  @byte_to_bits_table (for byte <- 0..255 do
                         for <<(bit::1 <- <<byte>>)>>, do: bit
                       end)
                      |> List.to_tuple()
  @empty_hash Hash.zero()

  defmemo encode_leaf_cached(key, value) do
    encode_leaf(key, value)
  end

  defmemo encode_branch_cached(left_hash, right_hash) do
    encode_branch(left_hash, right_hash)
  end

  defp split_trie_children(dict) do
    Enum.reduce(dict, {Map.new(), Map.new()}, fn
      {<<0::1, rest::bitstring>>, value}, {left_acc, right_acc} ->
        {Map.put(left_acc, rest, value), right_acc}

      {<<1::1, rest::bitstring>>, value}, {left_acc, right_acc} ->
        {left_acc, Map.put(right_acc, rest, value)}
    end)
  end

  defmemo(empty_leaf_hash(), do: Hash.default(encode_leaf_cached(<<>>, <<>>)))
  defmemo(empty_branch_hash(), do: Hash.default(encode_branch_cached(@empty_hash, @empty_hash)))

  @doc """
  Formula (D.3) v0.7.2:
     { (H, H) → b_512
  B: { (l,r) → [0] ~ bits(l)_1... ~ bits(r)

  Encodes the branch by concatenating the left and right hashes
  after using the bits order function.

  In the case of a branch, the remaining 511 bits are split between the two child node hashes,
  using the last 255 bits of the 0-bit (left) sub-trie identity and the full 256 bits of the 1-bit (right) sub-trie identity.
  """
  def encode_branch(l, r) do
    <<_::1, rest::bitstring>> = l
    <<0::1, rest::bitstring, r::bitstring>>
  end

  @doc """
    Formula (D.4) v0.7.2
    Encodes the leaf nodes distinguin between regular and embedded leafs.
      { (H, Y) → b_512
    L:{ (k, v）→{ [1,0] ~  bits(E1(|v|)_2... ~  bits(k)...248 ~ bits(v) ~ [0,0,...]  if|v|≤32
              { [1,1,0,0,0,0,0,0] ~ bits(k)...248 ~ bits(H(v))                    otherwise

  Leaf nodes are further subdivided into embedded-value leaves and regular leaves. The second bit of the node discriminates between these.
  In the case of an embedded-value leaf, the remaining 6 bits of the first byte are used to store the embedded value size. The following 31 bytes
  are dedicated to the first 31 bytes of the key. The last 32 bytes are defined as the value, filling with zeroes if its length is less than 32 bytes.
  In the case of a regular leaf, the remaining 6 bits of the first byte are zeroed. The following 31 bytes store the first 31 bytes of the key. The last
  32 bytes store the hash of the value.
  Formally, we define the encoding functions B and L:
  """

  def encode_leaf(key, value) do
    size = byte_size(value)

    if size <= 32 do
      <<_::2, size_part::bitstring>> = e_le(size, 1)
      result = <<0b10::2, size_part::bitstring, key::bitstring, value::bitstring>>
      <<result::bitstring, 0::size(512 - bit_size(result))>>
    else
      hvalue = Hash.default(value)
      <<0b11000000, key::bitstring, hvalue::bitstring>>
    end
  end

  def merkelize_state(%SerializedState{data: dict}), do: merkelize_state(dict)

  # Formula (D.5) v0.7.2
  # M(σ）= M（｛（bits(k) →（K,v））|（K → v）∈ T（σ）)
  def merkelize_state(dict) do
    merkelize(
      for {k, v} <- dict do
        {<<k::bitstring>>, {k, v}}
      end
      |> Enum.into(%{})
    )
  end

  @doc """
  General Merklization Function

  Formula (D.6) v0.7.2
                           { H°                        if |d| = 0
    M(d: <b → (B_31,B)>) = { H(bits-1 (L(k,v)))        if V（d） =｛（k，v）｝
                           { H(bits-1 (B(M(l), M(r)))) otherwise,
                           where Vb,p: (b → p) ∈ d ⇔ (b_1... → p) ∈ { l   if b_0 = 0
                                                                    { r   if b_0 = 1
  """

  def merkelize(dict) do
    case map_size(dict) do
      0 ->
        @empty_hash

      1 ->
        [{k, v}] = Map.values(dict)

        if k == <<>> and v == <<>> do
          empty_leaf_hash()
        else
          Hash.default(encode_leaf_cached(k, v))
        end

      _ ->
        {l, r} = split_trie_children(dict)

        left_hash = merkelize(l)
        right_hash = merkelize(r)

        if left_hash == @empty_hash and right_hash == @empty_hash do
          empty_branch_hash()
        else
          Hash.default(encode_branch_cached(left_hash, right_hash))
        end
    end
  end

  @doc """
  section 3.7.3
  Bits function, convers Bytes into octets.
  We use the function bits(Y) ∈ B to denote the sequence of bits, ordered with the least significant first,
  which represent the octet sequence Y, thus bits([5,0]) = [1,0,1,0,0,...].

  """
  def bits(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.flat_map(&elem(@byte_to_bits_table, &1))
  end
end
