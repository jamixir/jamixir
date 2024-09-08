defmodule ErasureCoding do
  # Formula (314) v0.3.4
  def split(data, n) when is_binary(data) do
    data |> :binary.bin_to_list() |> split(n)
  end

  def split(data, n) when is_list(data) do
    data
    |> Enum.chunk_every(n, n, :discard)
    |> Enum.map(&:binary.list_to_bin/1)
  end

  # Formula (315) v0.3.4
  defp join(chunks) when is_list(chunks) do
    chunks
    |> Enum.reduce(<<>>, fn chunk, acc -> acc <> chunk end)
  end

  # Formula (316) v0.3.4
  defp transpose(matrix) when is_list(matrix) do
    matrix
    |> List.zip()
    |> Enum.map(&Tuple.to_list/1)
  end

  def encode(<<>>, _n), do: <<>>

  def encode(d, n) when is_binary(d) do
    d
    |> split(n)
    |> Enum.map(&c(:binary.bin_to_list(&1)))
    |> transpose()
    |> Enum.map(&join/1)
  end

  def c(data) do
    data
  end

  use Rustler, otp_app: :jamixir, crate: :erasure_coding

  def encode_native(_size, _binary), do: :erlang.nif_error(:nif_not_loaded)
end
