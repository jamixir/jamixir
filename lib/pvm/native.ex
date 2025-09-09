defmodule Pvm.Native do
  use Rustler, otp_app: :jamixir, crate: "pvm"

  def execute(_program, _counter, _gas, _args) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
