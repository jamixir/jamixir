defmodule Util.MMR do
  @moduledoc """
  A Merkle Mountain Range (MMR) implementation.
  Appendix E.2
  """

  alias Util.{Hash, MMR}

  @type t :: %MMR{roots: [Types.hash() | nil]}
  defstruct roots: []

  @doc """
  Create a new empty MMR.
  """
  def new do
    %MMR{}
  end

  @doc """
  Create a new MMR from a list of hashes.
  """
  def from(list_of_hashes) do
    %MMR{roots: list_of_hashes}
  end

  @doc """
  Convert an MMR to a list of hashes.
  """
  def to_list(%MMR{roots: roots}), do: roots

  @doc """
  Add a new element to the MMR.
  Formula (326) v0.4.1 - A
  """
  def append(%MMR{roots: roots} = mmr, hash) do
    new_roots = append_root(roots, hash)
    %MMR{mmr | roots: new_roots}
  end

  # Formula (326) v0.4.1 - A
  defp append_root(roots, hash), do: append_root(roots, hash, 0)

  # Formula (326) v0.4.1 - P
  defp append_root(roots, hash, n) do
    if n >= length(roots) do
      roots ++ [hash]
    else
      current_root = Enum.at(roots, n)

      if current_root == nil do
        replace(roots, n, hash)
      else
        combined_hash = Hash.default(current_root <> hash)
        updated_roots = replace(roots, n, nil)
        append_root(updated_roots, combined_hash, n + 1)
      end
    end
  end

  # Formula (326) v0.4.1 - R
  defp replace(roots, i, value) do
    List.replace_at(roots, i, value)
  end
end
