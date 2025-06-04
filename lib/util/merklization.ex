defmodule Util.Merklization do
  @moduledoc """
  Apendix D. STATE MERKLIZATION
  D.2. Merklization
  D.2.1. Node Encoding and Trie Identification

  """

  alias Util.Hash
  import Codec.Encoder

  @doc """
  Formula (D.3) v0.6.5:
     { (H, H) → B512
  B: { (l,r) → [0] ~ bits(l)1... ~ bits(r)

  Encodes the branch by concatenating the left and right hashes
  after using the bits order function.

  In the case of a branch, the remaining 511 bits are split between the two child node hashes,
  using the last 255 bits of the 0-bit (left) sub-trie identity and the full 256 bits of the 1-bit (right) sub-trie identity.
  """
  def encode_branch(l, r) do
    [_ | rest] = bits(l)
    [0] ++ rest ++ bits(r)
  end

  @doc """
    Formula (D.4) v0.6.5
    Encodes the leaf nodes distinguin between regular and embedded leafs.
      { (H, Y) → B512
    L:{ (k, v）→{ [1,0] ~  bits(E1(|v|)2... ~  bits(k)...248 ~ bits(v) ~ [0,0,...]  if|v|≤32
              { [1,1,0,0,0,0,0,0] ~ bits(k)...248 ~ bits(H(v))                    otherwise

  Leaf nodes are further subdivided into embedded-value leaves and regular leaves. The second bit of the node discriminates between these.
  In the case of an embedded-value leaf, the remaining 6 bits of the first byte are used to store the embedded value size. The following 31 bytes
  are dedicated to the first 31 bytes of the key. The last 32 bytes are defined as the value, filling with zeroes if its length is less than 32 bytes.
  In the case of a regular leaf, the remaining 6 bits of the first byte are zeroed. The following 31 bytes store the first 31 bytes of the key. The last
  32 bytes store the hash of the value.
  Formally, we define the encoding functions B and L:
  """

  def encode_leaf(key, value) do
    if byte_size(value) <= 32 do
      result =
        [1, 0] ++
          (bits(e_le(byte_size(value), 1)) |> Enum.drop(2)) ++
          (bits(key) |> Enum.take(248)) ++
          bits(value)

      result ++ List.duplicate(0, 512 - length(result))
    else
      [1, 1, 0, 0, 0, 0, 0, 0] ++ (bits(key) |> Enum.take(248)) ++ bits(Hash.default(value))
    end
  end

  @doc """
    Merklization State Function

   Formula (D.5) v0.6.5
    Mo（o）= M（｛（bits(k) →（K,v））|（K → v）E T（o）)

  """
  def merkelize_state(dict) do
    merkelize(
      for {k, v} <- dict do
        {bits(k), {k, v}}
      end
      |> Enum.into(%{})
    )
  end

  @doc """
    General Merklization Function

   Formula (D.6) v0.6.5
                       { H°                       if |d| = 0
    M(d:D(B → (H,Y))) ={ H(bits-1 (L(k,v)))        if V（d） =｛（k，v）｝
                       { H(bits-1 (B(M(l), M(r)))) otherwise, where Vb,p: (b → p) ed → (b1.. → p) E { l   if bo = 0
                                                                                                    { r   if bo = 1
  """

  def merkelize(dict) do
    case map_size(dict) do
      0 ->
        Hash.zero()

      1 ->
        [{_, {k, v}}] = Map.to_list(dict)
        Hash.default(bits_to_bytes(encode_leaf(k, v)))

      _ ->
        {l, r} =
          dict
          |> Enum.split_with(fn {[b0 | _], _} -> b0 == 0 end)
          |> (fn {left, right} ->
                {
                  for({[_ | rest], value} <- left, do: {rest, value}, into: %{}),
                  for({[_ | rest], value} <- right, do: {rest, value}, into: %{})
                }
              end).()

        Hash.default(bits_to_bytes(encode_branch(merkelize(l), merkelize(r))))
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
    |> Enum.flat_map(fn byte ->
      for <<(bit::1 <- <<byte>>)>>, do: bit
    end)
  end

  @doc """

  """

  def bits_to_bytes(bits) do
    for chunk <- Enum.chunk_every(bits, 8) do
      Enum.with_index(chunk |> Enum.reverse())
      |> Enum.reduce(0, fn {bit, index}, acc ->
        acc + bit * :math.pow(2, index)
      end)
      |> round()
    end
    |> :binary.list_to_bin()
  end
end
