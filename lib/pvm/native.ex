defmodule Pvm.Native do
  alias Pvm.Native.ExecuteResult
  use Rustler, otp_app: :jamixir, crate: "pvm"

  # VM execution entry point
  @spec execute(any(), any(), any(), any(), any()) :: ExecuteResult.t()
  def execute(_program, _pc, _gas, _args, _memory_ref) do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Resume VM after handling a host call
  def resume(_state, _memory_ref, _context_token) do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Create a new memory reference
  def memory_new do
    :erlang.nif_error(:nif_not_loaded)
  end

  def build_memory do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Read from shared memory
  def memory_read(_memory_ref, _addr, _len) do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Write to shared memory
  def memory_write(_memory_ref, _addr, _data) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def set_memory_access(_memory_ref, _addr, _len, _mode) do
    :erlang.nif_error(:nif_not_loaded)
  end
end

defmodule Pvm.Native.ExecuteResult do
  defstruct [:used_gas, :output, :context_token]
end

defmodule Pvm.Native.VmState do
  defstruct [:registers, :pc, :initial_gas, :spent_gas]
end
