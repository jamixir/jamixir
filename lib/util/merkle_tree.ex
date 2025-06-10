defmodule Util.MerkleTree do
  alias Util.Hash

  @doc """
    Constructs a well-balanced binary Merkle tree and returns the root hash.
    Formula (E.3) v0.6.6
  """
  @spec well_balanced_merkle_root(list(binary())) :: Types.hash()
  def well_balanced_merkle_root(l), do: well_balanced_merkle_root(l, &Hash.default/1)
  @spec well_balanced_merkle_root(list(binary()), (binary() -> Types.hash())) :: Types.hash()
  def well_balanced_merkle_root([], _), do: raise(ArgumentError, "List of blobs cannot be empty")
  def well_balanced_merkle_root([single_blob], hash_func), do: hash_func.(single_blob)
  def well_balanced_merkle_root(list_of_blobs, hash_func), do: node(list_of_blobs, hash_func)

  # Formula (E.4) v0.6.6
  @spec merkle_root(list(binary())) :: Types.hash()
  def merkle_root(v), do: merkle_root(v, &Hash.default/1)
  @spec merkle_root(list(binary()), (binary() -> Types.hash())) :: Types.hash()
  def merkle_root(list, hash_func), do: node(c_preprocess(list, hash_func), hash_func)

  # Formula (E.7) v0.6.6
  @spec c_preprocess(list(binary()), (binary() -> Types.hash())) :: list(Types.hash())
  def c_preprocess([], _), do: [Hash.zero()]

  def c_preprocess(list, hash_func) do
    pad_to_power_of_two(for(x <- list, do: hash_func.("leaf" <> x)), Hash.zero())
  end

  # Formula (E.2) v0.6.6
  def trace(v, i, hash_func) when length(v) > 1 do
    [node(p(false, v, i), hash_func) | trace(p(true, v, i), i - pi(v, i), hash_func)]
  end

  def trace(_, _i, _hash_func), do: []

  # Formula (E.5) v0.6.6
  @spec justification([binary()], integer(), integer()) :: [binary()]
  def justification(v, i, x), do: justification(v, i, &Hash.default/1, x)

  # Formula (E.5) v0.6.6
  @spec justification([binary()], integer(), (binary() -> Types.hash()), number()) :: list()
  def justification([], _, hash_func, _) when is_function(hash_func, 1), do: []

  # (v,i,H) ↦ T(C(v,H),(2^x)*i,H)...max(0,⌈log2(max(1,∣v∣))−x⌉)
  @spec justification([binary()], integer(), (binary() -> Types.hash()), number()) :: list()
  def justification(v, i, hash_func, x) when x >= 0 and is_function(hash_func, 1) do
    size = max(0, ceil(:math.log2(max(1, length(v))) - x))
    trace(c_preprocess(v, hash_func), :math.pow(2, i) * x, hash_func) |> Enum.take(size)
  end

  # Formula (E.6) v0.6.6
  # (v, i, H) ↦ [H($leaf ⌢ l) S l <− v2xi... min(2xi+2x,SvS)]
  def justification_l(v, i, x), do: justification_l(v, i, &Hash.default/1, x)

  @spec justification_l([binary()], integer(), (binary() -> Types.hash()), number()) :: list()
  def justification_l(v, i, hash_func, x) do
    start_idx = trunc(:math.pow(2, x * i))
    end_idx = min(trunc(:math.pow(2, x * i) + :math.pow(2, x)), length(v))

    if start_idx > length(v) or start_idx > end_idx - 1 do
      []
    else
      for l <- Enum.slice(v, start_idx..(end_idx - 1)), do: hash_func.("leaf" <> l)
    end
  end

  @spec pi(list(), integer()) :: integer()
  def pi(v, i) do
    x = ceil(length(v) / 2)
    if i < x, do: 0, else: x
  end

  @spec p(boolean(), list(), integer()) :: list()
  def p(s, v, i) do
    x = ceil(length(v) / 2)

    if i < x == s do
      Enum.take(v, x)
    else
      Enum.take(v, -x)
    end
  end

  defp pad_to_power_of_two(list, pad_value) do
    next_power_of_two = next_power_of_two(length(list))
    padding = next_power_of_two - length(list)
    list ++ List.duplicate(pad_value, padding)
  end

  defp next_power_of_two(n) do
    :math.pow(2, Float.ceil(:math.log2(n))) |> round()
  end

  # Node function N for the Merkle tree.
  # Formula (E.1) v0.6.6
  @spec node(list(binary()), (binary() -> Types.hash())) :: binary() | Types.hash()
  def node([], _), do: Hash.zero()
  def node([single_blob], _), do: single_blob

  def node(list_of_blobs, hash_func) do
    mid = div(length(list_of_blobs), 2)
    {left, right} = Enum.split(list_of_blobs, mid)
    left_hash = node(left, hash_func)
    right_hash = node(right, hash_func)
    hash_func.("node" <> left_hash <> right_hash)
  end
end
