defmodule ErasureCoding do
  # Formula (H.1) v0.6.5
  @ec_size Constants.erasure_coded_piece_size()

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

  # Formula (H.2) v0.6.5
  def join(chunks, n) when is_list(chunks) do
    Enum.reduce(chunks, <<>>, fn chunk, acc ->
      if byte_size(chunk) != n do
        raise ArgumentError, "Invalid data size"
      end

      acc <> chunk
    end)
  end

  def join([]), do: <<>>

  def join([c | _] = chunks) when is_list(chunks) and is_binary(c) do
    join(chunks, byte_size(c))
  end

  def join([c | _] = chunks) when is_list(chunks) and is_list(c) do
    join(for c <- chunks, do: :binary.list_to_bin(c))
  end

  # Formula (H.3) v0.6.5
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

  # Formula (H.4) v0.6.5
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

  def erasure_code(bin) do
    Application.get_env(:jamixir, :erasure_coding, __MODULE__).do_erasure_code(bin)
  end

  @callback do_erasure_code(binary()) :: list(binary())
  def do_erasure_code(d) do
    for c <-
          Utils.transpose(
            for p <- unzip(d, @ec_size) do
              encode_bin(p)
            end
          ) do
      join(c)
    end
  end

  @spec encode_bin(binary) :: list(binary)
  def encode_bin(data)
      when is_binary(data) and byte_size(data) == @ec_size do
    data
    |> :binary.bin_to_list()
    |> Enum.chunk_every(2)
    |> encode()
  end

  def encode_bin(_), do: raise(ArgumentError, "Invalid data size")

  use Rustler, otp_app: :jamixir, crate: :erasure_coding

  def encode(_bin), do: :erlang.nif_error(:nif_not_loaded)
end
