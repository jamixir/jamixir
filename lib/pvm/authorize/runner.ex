defmodule PVM.Authorize.Runner do
  use GenServer
  import Pvm.Native
  alias Pvm.Native.ExecuteResult
  require Logger

  defstruct [
    :service_code,
    :encoded_args,
    :authorize_params,
    :parent,
    :context_token
  ]

  def start(service_code, encoded_args, authorize_params, opts \\ []) do
    GenServer.start(
      __MODULE__,
      {service_code, encoded_args, authorize_params, self(), opts}
    )
  end

  @impl true
  def init({service_code, encoded_args, authorize_params, parent, _opts}) do
    state = %__MODULE__{
      service_code: service_code,
      encoded_args: encoded_args,
      authorize_params: authorize_params,
      parent: parent,
      context_token: nil
    }

    GenServer.cast(self(), :execute)
    {:ok, state}
  end

  @impl true
  def handle_cast(:execute, %{service_code: sc, encoded_args: a} = st) do
    case execute(sc, 0, Constants.gas_is_authorized(), a) do
      %ExecuteResult{output: :waiting, context_token: token} ->
        # VM paused on host call; wait for :ecall message
        {:noreply, %{st | context_token: token}}

      %ExecuteResult{output: output, used_gas: used_gas} ->
        send(st.parent, {used_gas, output})
        {:stop, :normal, st}
    end
  end

  @impl true
  def handle_info({:ecall, host_call_id, state, mem_ref, context_token}, st) do
    %Pvm.Native.VmState{registers: registers, spent_gas: spent_gas, initial_gas: initial_gas} =
      state

    gas_remaining = initial_gas - spent_gas

    #  the assumption here is that converting once to tuple is faster then using list inside the host call
    #  also just lazy to change all the host calls code to use list
    registers_struct = PVM.Registers.from_list(registers)

    {exit_reason, post_host_call_state} =
      PVM.Authorize.handle_host_call(
        host_call_id,
        %{gas: gas_remaining, registers: registers_struct, memory_ref: mem_ref},
        st.authorize_params
      )

    gas_consumed = gas_remaining - post_host_call_state.gas
    spent_gas = state.spent_gas + gas_consumed

    case exit_reason do
      :out_of_gas ->
        send(st.parent, {spent_gas, :out_of_gas})
        {:stop, :normal, st}

      :halt ->
        start_addr = elem(post_host_call_state.registers.r, 7)
        length = elem(post_host_call_state.registers.r, 8)

        result =
          case memory_read(mem_ref, start_addr, length) do
            {:ok, data} ->
              {spent_gas, data}

            {:error, _error} ->
              {spent_gas, <<>>}
          end

        send(st.parent, result)
        {:stop, :normal, st}

      :continue ->
        registers_list = PVM.Registers.to_list(post_host_call_state.registers)

        updated_state = %Pvm.Native.VmState{
          state
          | registers: registers_list,
            spent_gas: spent_gas
        }

        send(self(), {:resume_vm, mem_ref, updated_state, context_token})
        {:noreply, st}

      _ ->
        send(st.parent, {spent_gas, :panic})
        {:stop, :normal, st}
    end
  end

  def handle_info({:resume_vm, mem_ref, updated_state, context_token}, st) do
    case resume(updated_state, mem_ref, context_token) do
      %ExecuteResult{output: :waiting, context_token: _token} ->
        {:noreply, st}

      %ExecuteResult{} = final ->
        send(st.parent, {final.used_gas, final.output})
        {:stop, :normal, st}
    end
  end

  # Handle any unexpected messages
  def handle_info(_, st) do
    {:noreply, st}
  end
end
