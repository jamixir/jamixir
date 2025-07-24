defmodule ErasureCoding do
  def erasure_code(bin) do
    Application.get_env(:jamixir, :erasure_coding, __MODULE__).do_erasure_code(bin)
  end

  @callback do_erasure_code(binary()) :: list(binary())
  def do_erasure_code(d) do
    encode(d, Constants.core_count())
  end

  use Rustler, otp_app: :jamixir, crate: :erasure_coding

  # coveralls-ignore-start
  def encode(_bin, _c), do: :erlang.nif_error(:nif_not_loaded)
  def decode(_shards, _indices, _size, _c), do: :erlang.nif_error(:nif_not_loaded)
end
