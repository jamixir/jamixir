defmodule Util.HexNative do
  use Rustler, otp_app: :jamixir, crate: :hex_helper

  def encode16(_data, _case \\ :lower), do: :erlang.nif_error(:nif_not_loaded)

  def decode16(_hex_str), do: :erlang.nif_error(:nif_not_loaded)
end
