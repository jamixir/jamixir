defmodule Util.Hex do
  use Memoize
  @doc """
  Decodes a hex string that may optionally start with "0x"
  """
  defmemo decode16(hex_str, opts \\ [case: :lower])
  defmemo decode16("0x" <> hex_str, opts), do: Base.decode16(hex_str, opts)
  defmemo decode16(hex_str, opts), do: Base.decode16(hex_str, opts)

  defmemo decode16!(hex_str, opts \\ [case: :lower])
  defmemo decode16!("0x" <> hex_str, opts), do: Base.decode16!(hex_str, opts)
  defmemo decode16!(hex_str, opts), do: Base.decode16!(hex_str, opts)

  defmemo encode16(binary, opts \\ [])

  defmemo encode16(binary, case: casing, prefix: prefix) do
    hex = Base.encode16(binary, case: casing)
    if prefix, do: "0x" <> hex, else: hex
  end

  defmemo encode16(binary, opts) do
    casing = Keyword.get(opts, :case, :lower)
    prefix = Keyword.get(opts, :prefix, false)
    encode16(binary, case: casing, prefix: prefix)
  end

  def b16(binary), do: encode16(binary, prefix: true)
end
