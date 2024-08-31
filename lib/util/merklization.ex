defmodule Merklization do
  @moduledoc """
  Apendix D. STATE MERKLIZATION
  D.2. Merklization
  D.2.1. Encoding and Trie Identification
  """
  alias Util.Hash

  @doc """
    Formula (290) v0.3.6
  """
  def encode_branch(left_hash, right_hash) do
    content = <<0::1, left_hash::binary-size(256), right_hash::binary-size(256)>>
    hashed_branch = Hash.default(content)
    hashed_branch
  end

  @doc """
    Formula (291) v0.3.6
  """
  def encode_leaf(key, hash_value) do
    <<key_intern::binary-size(31), _rest_key::binary>> = key

    <<1::1, leaf_type::1, value_size::6, _key_value::binary-size(248), value_content::binary>> = hash_value

    leaf_type =
      case leaf_type do
        0 -> :embedded
        1 -> :regular
      end

    if leaf_type == :embedded and byte_size(value_content) <= 32 do
      # If the content is less than 32 bytes, pad with zeros
      padded_value_content =
        if byte_size(value_content) < 32 do
          value_content <> <<0::size((32 - byte_size(value_content)) * 8)>>
        else
          value_content
        end

      # Encode the content
      content =
        <<1::1, 1::1, value_size::6, key_intern::binary-size(31), padded_value_content::binary-size(256)>>

      result = Hash.default(content)
      result
    else
      # Regular value
      hashed_value = Hash.blake2b_256(value_content)
      content = <<1::1, 0::1, 0::6, key_intern::binary-size(31), hashed_value::binary-size(256)>>
      result = Hash.default(content)
      result
    end
  end

  @doc """
    Formula (292) and (293) v0.3.6
  """
  def merklize(key, hash_value) do
    if byte_size(hash_value) == 0 do
      Hash.default(<<0::512>>)
    else
      <<type_node::1, _::binary>> = hash_value

      case type_node do
        # Leaf Node
        1 ->
          encode_leaf(key, hash_value)

        # Branch node
        0 ->
          # Divide the branch hash_value into left and right
          <<left_hash::binary-size(256), right_hash::binary>> = hash_value
          encode_branch(left_hash, right_hash)
      end
    end
  end
end
