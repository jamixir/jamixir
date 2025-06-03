defmodule ErasureCoding do
  @ec_size Constants.erasure_coded_piece_size()

  def erasure_code(bin) do
    Application.get_env(:jamixir, :erasure_coding, __MODULE__).do_erasure_code(bin)
  end

  @callback do_erasure_code(binary()) :: list(binary())
  def do_erasure_code(d) do
    encode(d, Constants.core_count())
  end

  use Rustler, otp_app: :jamixir, crate: :erasure_coding

  def encode(_bin, _c), do: :erlang.nif_error(:nif_not_loaded)
end
