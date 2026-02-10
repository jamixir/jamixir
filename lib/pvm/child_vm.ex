defmodule PVM.ChildVm do


  @type t :: %__MODULE__{
          program: binary(),
          vm_instance_ref: reference(),
          counter: non_neg_integer()
        }

  defstruct [
    program: <<>>,
    vm_instance_ref: nil,
    counter: 0
  ]


  def new(program_blob, initial_pc, initial_gas \\ 0) do
    # Child VMs always start with zero registers
    registers = List.duplicate(0, 13)

    case Pvm.Native.create_child_vm(program_blob, initial_pc, initial_gas, registers) do
      {:ok, vm_ref} when is_reference(vm_ref) ->
        %__MODULE__{
          program: program_blob,
          vm_instance_ref: vm_ref,
          counter: initial_pc
        }

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_result, other}}
    end
  end


  def execute(%__MODULE__{vm_instance_ref: vm_ref} = machine, gas, registers) do
    case Pvm.Native.execute_child_vm(vm_ref, gas, registers) do
      {exit_reason, %Pvm.Native.VmState{} = vm_state} ->
        updated_machine = %{machine | counter: vm_state.pc}
        {exit_reason, updated_machine, vm_state}

      error ->
        {:error, error}
    end
  end

  def read_memory(%__MODULE__{vm_instance_ref: vm_ref}, addr, len) do
    Pvm.Native.child_vm_read_memory(vm_ref, addr, len)
  end


  def write_memory(%__MODULE__{vm_instance_ref: vm_ref}, addr, data) do
    Pvm.Native.child_vm_write_memory(vm_ref, addr, data)
  end


  def get_state(%__MODULE__{vm_instance_ref: vm_ref}) do
    Pvm.Native.get_child_vm_state(vm_ref)
  end


  def destroy(%__MODULE__{vm_instance_ref: vm_ref}) do
    Pvm.Native.destroy_child_vm(vm_ref)
  end

  def set_memory_access(%__MODULE__{vm_instance_ref: vm_ref}, page_index, page_count, permission) do
    Pvm.Native.set_child_vm_memory_access(vm_ref, page_index, page_count, permission)
  end


  def check_memory_access(%__MODULE__{vm_instance_ref: vm_ref}, page_index, page_count, required_permission) do
    Pvm.Native.check_child_vm_memory_access(vm_ref, page_index, page_count, required_permission)
  end


  def zero_memory(%__MODULE__{vm_instance_ref: vm_ref}, addr, len) do
    Pvm.Native.child_vm_zero_memory(vm_ref, addr, len)
  end

  def zero_pages(%__MODULE__{} = machine, page_index, page_count) do
    page_size = PVM.Memory.Constants.page_size()
    start_addr = page_index * page_size
    length = page_count * page_size
    zero_memory(machine, start_addr, length)
  end
end
