defmodule ErasureCoding do
  # Formula (H.1) v0.5.4

  def split(data, n) when is_binary(data) and rem(byte_size(data), n) != 0 do
    raise ArgumentError, "Invalid data size"
  end

  def split(data, n) when is_binary(data) do
    data |> :binary.bin_to_list() |> split(n)
  end

  def split(data, n) when is_list(data) do
    data
    |> Enum.chunk_every(n, n, :discard)
    |> Enum.map(&:binary.list_to_bin/1)
  end

  # Formula (H.2) v0.5.4
  def join(chunks, n) when is_list(chunks) do
    Enum.reduce(chunks, <<>>, fn chunk, acc ->
      if byte_size(chunk) != n do
        raise ArgumentError, "Invalid data size"
      end

      acc <> chunk
    end)
  end

  def join([]), do: <<>>

  def join([c | _] = chunks) when is_list(chunks) do
    join(chunks, byte_size(c))
  end

  # Formula (H.3) v0.5.4
  def unzip(<<>>, _), do: []

  def unzip(data, n) when rem(byte_size(data), n) != 0 do
    raise ArgumentError, "Invalid data size"
  end

  def unzip(data, n) when is_binary(data) do
    k = div(byte_size(data), n)

    for i <- 0..(k - 1) do
      for j <- 0..(n - 1) do
        :binary.at(data, i + j * k)
      end
      |> :binary.list_to_bin()
    end
  end

  # Formula (H.4) v0.5.4
  def lace([], _), do: <<>>

  def lace(chunks, n) when is_list(chunks) do
    k = length(chunks)

    for j <- 0..(n - 1), into: <<>> do
      for i <- 0..(k - 1), into: <<>> do
        b = Enum.at(chunks, i)

        if byte_size(b) != n do
          raise ArgumentError, "Invalid data size"
        end

        <<:binary.at(b, j)>>
      end
    end
  end

  def lace([]), do: <<>>
  def lace([c | _] = chunks) when is_list(chunks), do: lace(chunks, byte_size(c))

  # Formula (H.5) v0.5.3
  def transpose([]), do: []

  def transpose([first | _] = matrix) when is_binary(first) do
    matrix
    |> Enum.map(&:binary.bin_to_list/1)
    |> List.zip()
    |> Enum.map(&Tuple.to_list(&1))
    |> Enum.map(&:binary.list_to_bin/1)
  end

  def transpose([first | _] = matrix) when is_list(matrix) and is_list(first) do
    List.zip(matrix) |> Enum.map(&Tuple.to_list/1)
  end

  def encode(<<>>, _n), do: <<>>

  def encode(d, n) when is_binary(d) do
    d
    |> split(n)
    |> Enum.map(&c(:binary.bin_to_list(&1)))
    |> transpose()
    |> Enum.map(&join(&1, n))
  end

  def c(data) do
    data
  end

  def erasure_code(d) do
    for c <-
          transpose(
            for p <- unzip(d, 684) do
              c(p)
            end
          ) do
      join(c)
    end
  end

  @spec encode_bin(binary) :: list(binary)
  def encode_bin(data) when is_binary(data) and byte_size(data) == 684 do
    data
    |> :binary.bin_to_list()
    |> Enum.chunk_every(2)
    |> encode()
  end

  def encode_bin(_), do: raise(ArgumentError, "Invalid data size")

  use Rustler, otp_app: :jamixir, crate: :erasure_coding

  def encode(_bin), do: :erlang.nif_error(:nif_not_loaded)
end
