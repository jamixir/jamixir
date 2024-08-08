defmodule ScaleNative do
  use Rustler, otp_app: :jamixir, crate: :scale

  def encode_integer(_number), do: :erlang.nif_error(:nif_not_loaded)
  def decode_integer(_vector), do: :erlang.nif_error(:nif_not_loaded)
end
