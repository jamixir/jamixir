defmodule PVM.OnTransfer.Runner do
  use GenServer
  import Pvm.Native
  alias Pvm.Native.ExecuteResult
  require Logger

  defstruct [
    :service_code,
    :gas,
    :encoded_args,
    :service,
    :params,
    :parent,
    :context_token
  ]

  def start(service_code, service, encoded_args, gas, params, opts \\ []) do
    GenServer.start(
      __MODULE__,
      {service_code, service, encoded_args, gas, params, self(), opts}
    )
  end

  @impl true
  def init({service_code, service, encoded_args, gas, params, parent, _opts}) do
    state = %__MODULE__{
      service_code: service_code,
      gas: gas,
      encoded_args: encoded_args,
      params: params,
      service: service,
      parent: parent,
      context_token: nil
    }

    GenServer.cast(self(), :execute)
    {:ok, state}
  end

  @impl true
  def handle_cast(:execute, %{service_code: sc, gas: g, encoded_args: a} = st) do
    case execute(sc, 10, g, a) do
      %ExecuteResult{output: :waiting, context_token: token} ->
        # VM paused on host call; wait for :ecall message
        {:noreply, %{st | context_token: token}}

      %ExecuteResult{used_gas: used_gas} ->
        send(st.parent, {used_gas, st.service})
        {:stop, :normal, st}
    end
  end

  @impl true
  def handle_info({:ecall, host_call_id, state, mem_ref, context_token}, st) do
    %Pvm.Native.VmState{registers: registers, spent_gas: spent_gas, initial_gas: initial_gas} =
      state

    gas_remaining = initial_gas - spent_gas

    registers_struct = PVM.Registers.from_list(registers)

    {exit_reason, post_host_call_state, context} =
      PVM.OnTransfer.handle_host_call(
        host_call_id,
        %{gas: gas_remaining, registers: registers_struct, memory_ref: mem_ref},
        st.service,
        st.params
      )

    gas_consumed = gas_remaining - post_host_call_state.gas
    spent_gas = state.spent_gas + gas_consumed

    case exit_reason do
      :out_of_gas ->
        send(st.parent, {spent_gas, :out_of_gas, context})
        {:stop, :normal, st}

      :halt ->
        start_addr = elem(post_host_call_state.registers.r, 7)
        length = elem(post_host_call_state.registers.r, 8)

        result =
          case memory_read(mem_ref, start_addr, length) do
            {:ok, data} ->
              {spent_gas, data, context}

            {:error, _error} ->
              {spent_gas, <<>>, context}
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
        {:noreply, %{st | service: context}}

      _ ->
        send(st.parent, {spent_gas, :panic, st.service})
        {:stop, :normal, st}
    end
  end

  def handle_info({:resume_vm, mem_ref, updated_state, context_token}, st) do
    case resume(updated_state, mem_ref, context_token) do
      %ExecuteResult{output: :waiting, context_token: _token} ->
        {:noreply, st}

      %ExecuteResult{} = final ->
        send(st.parent, {final.used_gas, st.service})
        {:stop, :normal, st}
    end
  end

  # Handle any unexpected messages
  def handle_info(_, st) do
    {:noreply, st}
  end
end
