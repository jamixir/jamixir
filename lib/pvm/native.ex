defmodule Pvm.Native do
  alias Pvm.Native.ExecuteResult
  use Rustler, otp_app: :jamixir, crate: "pvm"

  # VM execution entry point
  @spec execute(any(), any(), any(), any()) :: ExecuteResult.t()
  def execute(_program, _pc, _gas, _args) do
    :erlang.nif_error(:nif_not_loaded)
  end

  # Resume VM after handling a host call
  def resume(_state, _memory_ref, _context_token) do
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

  def memory_access?(memory_ref, addr, len, mode),
    do: check_memory_access(memory_ref, addr, len, mode)

  def check_memory_access(_memory_ref, _addr, _len, _mode) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def create_child_vm(_program_blob, _pc, _gas, _registers) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def execute_child_vm(_instance_ref, _gas, _registers) do
    :erlang.nif_error(:nif_not_loaded)
  end


  def child_vm_read_memory(_instance_ref, _addr, _len) do
    :erlang.nif_error(:nif_not_loaded)
  end


  def child_vm_write_memory(_instance_ref, _addr, _data) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def get_child_vm_state(_instance_ref) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def destroy_child_vm(_instance_ref) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def validate_program_blob(_program_blob) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def set_child_vm_memory_access(_instance_ref, _page_index, _page_count, _permission) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def check_child_vm_memory_access(
        _instance_ref,
        _page_index,
        _page_count,
        _required_permission
      ) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def child_vm_zero_memory(_instance_ref, _addr, _len) do
    :erlang.nif_error(:nif_not_loaded)
  end
end

defmodule Pvm.Native.ExecuteResult do
  defstruct [:used_gas, :output, :context_token]
end

defmodule Pvm.Native.VmState do
  defstruct [:registers, :pc, :initial_gas, :spent_gas]
end
