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
  def to_list(%MMR{roots: r}), do: r

  @doc """
  Add a new element to the MMR.
  Formula (E.8) v0.6.0 - A
  """
  def append(%MMR{roots: r} = mmr, l, h \\ &Hash.default/1) do
    %MMR{mmr | roots: append_root(r, l, 0, h)}
  end

  # Formula (E.8) v0.6.0 - P
  defp append_root(r, l, n, h) do
    if n >= length(r) do
      r ++ [l]
    else
      case Enum.at(r, n) do
        nil -> replace(r, n, l)
        rn -> append_root(replace(r, n, nil), h.(rn <> l), n + 1, h)
      end
    end
  end

  # Formula (E.8) v0.6.0 - R
  defp replace(s, i, v) do
    List.replace_at(s, i, v)
  end
end
