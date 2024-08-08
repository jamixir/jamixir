defmodule Jamixir.ScaleNative do
  use Rustler, otp_app: :jamixir, crate: :scale

  def encode_compact_integer(_number), do: :erlang.nif_error(:nif_not_loaded)
end
