defmodule Util.Merklization do
  @moduledoc """
  Apendix D. STATE MERKLIZATION
  D.2. Merklization
  D.2.1. Node Encoding and Trie Identification

  We identif (sub-) tries as the hash of their root node, with one exception:
  empty (sub-) tries are identified as the zero-hash, H0.

  Nodes are fixed in size at 512 bit (64 bytes). Each node is either a branch or a
  leaf. The first bit discriminate between these two types.
  """

  alias Util.Hash

  @doc """
  Formula (293) v0.3.4:
     { (H, H) → B512
  B: { (l,r) → [0] ~ bits(l)1... ~ bits(r)

  Encodes the branch by concatenating the left and right hashes
  after using the bits order function.

  In the case of a branch, the remaining 511 bits are split between the two child node hashes,
  using the last 255 bits of the 0-bit (left) sub-trie identity and the full 256 bits of the 1-bit (right) sub-trie identity.
  """
  def encode_branch(left_hash, right_hash) do
    # Convert left and right hashes to bits
    bits_left = bits(left_hash)
    bits_right = bits(right_hash)

    left_bitstring = :erlang.list_to_bitstring(bits_left)
    bit_size = bit_size(left_bitstring)
    <<_::size(bit_size - 255), last_255_bits_left::bitstring-size(255)>> = left_bitstring

    # Extract the first 255 bits from the right hash
    <<first_255_bits_right::bitstring-size(255), _::bitstring>> =
      :erlang.list_to_bitstring(bits_right)

    # Combine into a 512-bit result
    <<0::1, last_255_bits_left::bitstring-size(255), 1::1,
      first_255_bits_right::bitstring-size(255)>>
  end

  @doc """
    Formula (294) v0.3.4
    Encodes the leaf nodes distinguin between regular and embedded leafs.
      { (H, Y) → B512
    L:{ （k,v）→{ [1,0] ~  bits(E1(|v|)...6 ~  bits(k)...248 ~ bits(v) ~ [0,0,...]  if|v|≤32
               { [1,1,0,0,0,0,0,0] ~ bits(k)...248 ~ bits(H(v))                    otherwise

      Leaf nodes are further subdivided into embedded-value leaves and regular leaves. The second bit of the node discriminates between these.
  In the case of an embedded-value leaf, the remaining 6 bits of the first byte are used to store the embedded value size. The following 31 bytes
  are dedicated to the first 31 bytes of the key. The last 32 bytes are defined as the value, filling with zeroes if its length is less than 32 bytes.
  In the case of a regular leaf, the remaining 6 bits of the first byte are zeroed. The following 31 bytes store the first 31 bytes of the key. The last 32 bytes store the hash of the value.
  Formally, we define the encoding functions B and L:
  """
def encode_leaf(key, value) do
  key_bytes = binary_part(key, 0, min(byte_size(key), 31))
  key_padded = String.pad_trailing(key_bytes, 31, <<0>>)

  bits_value = bits(value)
  bits_key = bits(key_padded)

  cond do
    byte_size(value) <= 32 ->
      # Embedded-value leaf
      value_size = byte_size(value)

      # Convertir las listas de bits a bitstrings
      key_bitstring = :erlang.list_to_bitstring(bits_key)
      value_bitstring = :erlang.list_to_bitstring(bits_value)

      # Codificar la hoja con el valor embebido en formato de bits
      <<1::1, 1::1, value_size::6, key_bitstring::bitstring-size(31 * 8), value_bitstring::bitstring-size(32 * 8)>>

    true ->
      # Regular leaf
      hashed_value = Hash.blake2b_256(value)
      bits_hashed_value = bits(hashed_value)
      value_bitstring = :erlang.list_to_bitstring( bits_hashed_value)
      <<1::1, 0::1, 0::6, key_padded::binary-size(31), value_bitstring::binary-size(32)>>
  end
end

  @doc """
    Formula  v0.3.4
    General Merklization Function

   Formula (295) v0.3.4
    Mo（o）= M（｛（bits(k) →（K,v））|（K → v）E T（o）)

   Formula (296) v0.3.4
                       { H°                       if |d| = 0
    M(d:D(B → (H,Y))) ={ H(bits-1 (L(k,v)))        if V（d） =｛（k，v）｝
                       { H(bits-1 (B(M(l), M(r)))) otherwise, where Vb,p: (b → p) ed → (b1.. → p) E { l   if bo = 0
                                                                                                  { r   if bo = 1
  """
  def merklize(value) do
    if bit_size(value) == 0 do
      result = Hash.default(value)
      result
    else
      <<type_node::1, _::bitstring>> = value

      case type_node do
        # Leaf Node
        1 ->
          <<_::8, key::bitstring-size(248), _rest::bitstring-size(256)>> = value

          result = encode_leaf(key, value)
          result

        # Branch node
        0 ->
          <<left_hash::bitstring-size(256), right_hash::bitstring-size(256)>> = value
          result = encode_branch(left_hash, right_hash)
          result
      end
    end
  end

  @doc """
  section 3.7.3
  Bits function, convers Bytes into octets.
  We use the function bits(Y) ∈ B to denote the sequence of bits, ordered with the least signif- icant first, which represent the octet sequence Y, thus bits([5,0]) = [1,0,1,0,0,...].
  """
  def bits(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.flat_map(fn byte ->
      bits = for <<(bit::1 <- <<byte>>)>>, do: bit
      Enum.reverse(bits)
    end)
  end
end
