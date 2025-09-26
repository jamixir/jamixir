defmodule Util.Hex do
  @doc """
  Decodes a hex string that may optionally start with "0x"
  """
  def decode16(hex_str, opts \\ [case: "lower"])

  def decode16(hex_str, _opts) when is_binary(hex_str) do
    case Util.HexNative.decode16(hex_str) do
      {:ok, result} -> {:ok, result}
      {:error, _} -> :error
    end
  end

  def decode16!(hex_str, opts \\ [case: "lower"])

  def decode16!(hex_str, opts) do
    case decode16(hex_str, opts) do
      {:ok, result} -> result
      :error -> raise ArgumentError, "non-alphabet character found: #{inspect(hex_str)}"
    end
  end

  def encode16(binary, opts \\ [])

  def encode16(binary, case: casing, prefix: prefix) do
    hex = Base.encode16(binary, case: casing)
    if prefix, do: "0x" <> hex, else: hex
  end

  def encode16(binary, opts) do
    casing = Keyword.get(opts, :case, :lower)
    prefix = Keyword.get(opts, :prefix, false)
    encode16(binary, case: casing, prefix: prefix)
  end

  def b16(binary), do: encode16(binary, prefix: true)
end
