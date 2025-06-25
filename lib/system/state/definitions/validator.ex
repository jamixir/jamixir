defmodule System.State.Validator do
  @moduledoc """
   # Formula (6.8) v0.6.6
  """
  alias System.State.Validator
  import Codec.Encoder

  @type t :: %__MODULE__{
          # Formula (6.9) v0.6.6 - b
          bandersnatch: Types.bandersnatch_key(),
          # Formula (6.10) v0.6.6 - e
          ed25519: Types.ed25519_key(),
          # Formula (6.11) v0.6.6 - BLS
          bls: Types.bls_key(),
          # Formula (6.12) v0.6.6 - m
          metadata: <<_::1024>>
        }

  defstruct bandersnatch: <<>>, ed25519: <<>>, bls: <<>>, metadata: <<>>

  def key(v), do: v.bandersnatch <> v.ed25519 <> v.bls <> v.metadata

  defimpl Encodable do
    alias System.State.Validator

    def encode(%Validator{} = v) do
      Validator.key(v)
    end
  end

  def decode(<<
        bandersnatch::b(bandersnatch_key),
        ed25519::b(ed25519_key),
        bls::b(bls_key),
        metadata::b(metadata),
        rest::binary
      >>) do
    {%__MODULE__{
       bandersnatch: bandersnatch,
       ed25519: ed25519,
       bls: bls,
       metadata: metadata
     }, rest}
  end

  # Formula (6.14) v0.6.6
  @spec nullify_offenders(
          list(Validator.t()),
          MapSet.t(Types.ed25519_key())
        ) :: list(Validator.t())
  def nullify_offenders([], _), do: []

  def nullify_offenders([%__MODULE__{} | _] = next_validators, offenders) do
    for v <- next_validators, do: if(v.ed25519 in offenders, do: nullified(v), else: v)
  end

  def nullified(validator) do
    %__MODULE__{
      bandersnatch: <<0::size(bit_size(validator.bandersnatch))>>,
      ed25519: <<0::size(bit_size(validator.ed25519))>>,
      bls: <<0::size(bit_size(validator.bls))>>,
      metadata: <<0::size(bit_size(validator.metadata))>>
    }
  end

  use JsonDecoder

  def ip_address(%__MODULE__{metadata: metadata}) when byte_size(metadata) >= 18 do
    <<ip::binary-size(16), _::binary>> = metadata

    ip
    |> Util.Hex.encode16()
    |> String.codepoints()
    |> Enum.chunk_every(4)
    |> Enum.join(":")
  end

  def ip_address(_), do: nil

  @spec port(%__MODULE__{}) :: integer() | nil
  def port(%__MODULE__{metadata: metadata}) when byte_size(metadata) >= 18 do
    <<_::binary-size(16), port::little-16, _::binary>> = metadata
    port
  end

  def port(_), do: nil

  def ip_port(%__MODULE__{metadata: metadata}) do
    ip = ip_address(%__MODULE__{metadata: metadata})
    port = port(%__MODULE__{metadata: metadata})
    {ip, port}
  end

  def address(%__MODULE__{} = validator) do
    {ip, port} = ip_port(validator)
    if ip && port, do: "#{ip}:#{port}", else: nil
  end

  @doc """
  Find validator by IP address and port from a list of validators.
  If port is nil, it ignores port due to ephemeral port issues with inbound connections.
  """
  def find_by_ip(validators, ip, port \\ nil) when is_list(validators) and is_binary(ip) do
    Enum.find(validators, fn validator ->
      ip_address(validator) == ip && (port == nil || port(validator) == port)
    end)
  end

  def neighbours(_, prev, curr, next)
      when length(curr) != length(prev) or length(curr) != length(next) do
    MapSet.new()
  end

  def neighbours(%__MODULE__{} = v, prev, curr, next) do
    size = length(curr)
    row_size = floor(:math.sqrt(size))

    case Enum.find_index(curr, &(&1 == v)) do
      nil ->
        MapSet.new()

      i ->
        row_neighbors =
          for r <- 0..(size - 1),
              r != i,
              row(r, row_size) == row(i, row_size),
              do: Enum.at(curr, r)

        col_neigbors =
          for r <- 0..(size - 1),
              r != i,
              coloum(r, row_size) == coloum(i, row_size),
              do: Enum.at(curr, r)

        MapSet.new(row_neighbors ++ col_neigbors ++ [Enum.at(prev, i)] ++ [Enum.at(next, i)])
    end
  end

  defp row(index, row_size), do: div(index, row_size)
  defp coloum(index, row_size), do: rem(index, row_size)
end
