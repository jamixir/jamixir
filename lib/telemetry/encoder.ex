defmodule Jamixir.Telemetry.Encoder do
  @moduledoc """
  Encodes telemetry messages according to JIP-3 specification.
  Messages are encoded as: [4-byte length (little-endian)] ++ [message content]
  Message content uses JAM serialization (SCALE codec).

  Leverages the existing Codec.Encoder for JAM-compliant encoding.
  """

  import Codec.Encoder

  @doc """
  Get current timestamp in microseconds since JAM Common Era
  """
  def timestamp do
    time = Util.Time.current_time() * 1_000_000
    <<time::64-little>>
  end

  @doc """
  Encode a variable-length string (length-prefixed UTF-8)
  """
  def encode_string(str) when is_binary(str) do
    e(vs(str))
  end

  @doc """
  Encode an Option type (0 for None, 1 + value for Some)
  """
  def encode_option(nil), do: <<0>>
  def encode_option(value), do: <<1>> <> e(value)

  @doc """
  Encode a variable-length sequence with explicit length prefix
  """
  def encode_sequence(items) when is_list(items) do
    e(vs(items))
  end
end
