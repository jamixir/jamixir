defmodule Util.Merklization do
  @moduledoc """
  Apendix D. STATE MERKLIZATION
  D.2. Merklization
  D.2.1. Encoding and Trie Identification
  """
  alias Util.Hash

  @doc """
  Formula (293) v0.3.4
  Encodes the branch by concatenating the left and right hashes
  after hashing them with Blake2b-256 and extracting the relevant bits.
  """
  def encode_branch(left_value, right_value) do
    hash_left = Hash.blake2b_256(left_value)
    hash_right = Hash.blake2b_256(right_value)

    <<_::size(1), last_255_bits::bitstring-size(255)>> = hash_left

    result =
      <<0::size(1), last_255_bits::bitstring, hash_right::bitstring-size(256)>>

    result
  end

  @doc """
    Formula (294) v0.3.4
    Encodes the leaf nodes distinguin between regular and embedded leafs.
  """
  def encode_leaf(key, value) do
    <<_note_type::1, leaf_type::1, _Rest::bitstring>> = value
    <<key_intern::bitstring-size(248), _rest_key::bitstring>> = key

    leaf_type =
      case leaf_type do
        0 -> :embedded
        1 -> :regular
      end

    if leaf_type == :embedded and byte_size(value) <= 32 do
      hash_value = Hash.blake2b_n(value, 32)

      leaf_embebed_size = bit_size(hash_value)

      result =
        <<1::1, 1::1, leaf_embebed_size::6, key_intern::bitstring-size(248),
          hash_value::bitstring-size(256)>>

      result
    else
      # Regular value
      hashed_value = Hash.blake2b_256(value)

      result =
        <<1::1, 0::1, 0::6, key_intern::bitstring-size(248), hashed_value::bitstring-size(256)>>

      result
    end
  end

  @doc """
    Formula (295) and (296) v0.3.4
    General Merklization Function
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
end
