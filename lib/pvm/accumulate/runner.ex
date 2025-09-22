defmodule PVM.Accumulate.Runner do
  use GenServer
  import Pvm.Native
  alias Pvm.Native.ExecuteResult
  require Logger

  defstruct [
    :service_code,
    :gas,
    :encoded_args,
    :operands,
    :ctx_pair,
    :mem_ref,
    :parent,
    :n0_,
    :timeslot,
    :service_index,
    :context_token
  ]

  def start(
        service_code,
        initial_context,
        encoded_args,
        gas,
        operands,
        n0_,
        timeslot,
        service_index,
        opts \\ []
      ) do
    GenServer.start(
      __MODULE__,
      {service_code, initial_context, encoded_args, gas, operands, n0_, timeslot, service_index,
       self(), opts}
    )
  end

  @impl true
  def init(
        {service_code, initial_context, encoded_args, gas, operands, n0_, timeslot, service_index,
         parent, _opts}
      ) do
    ctx_pair = {initial_context, initial_context}

    mem_ref = memory_new()

    state = %__MODULE__{
      service_code: service_code,
      gas: gas,
      encoded_args: encoded_args,
      operands: operands,
      ctx_pair: ctx_pair,
      mem_ref: mem_ref,
      parent: parent,
      n0_: n0_,
      timeslot: timeslot,
      service_index: service_index,
      context_token: nil
    }

    GenServer.cast(self(), :execute)
    {:ok, state}
  end

  @impl true
  def handle_cast(:execute, %{service_code: sc, gas: g, encoded_args: a, mem_ref: mr} = st) do
    case execute(sc, 5, g, a, mr) do
      %ExecuteResult{output: :waiting, context_token: token} ->
        # VM paused on host call; wait for :ecall message
        {:noreply, %{st | context_token: token}}

      %ExecuteResult{output: output, used_gas: used_gas, context_token: _token} ->
        send(st.parent, {used_gas, output, st.ctx_pair})
        {:stop, :normal, st}
    end
  end

  @impl true
  def handle_info({:ecall, host_call_id, state, mem_ref, context_token}, st) do
    %Pvm.Native.VmState{
      registers: registers,
      spent_gas: spent_gas,
      initial_gas: initial_gas
    } = state

    gas_remaining = initial_gas - spent_gas

    #  the assumption here is that converting once to tuple is faster then using list inside the host call
    #  also just lazy to change all the host calls code to use list
    registers_struct = PVM.Registers.from_list(registers)

    {exit_reason, post_host_call_state, new_ctx_pair} =
      PVM.Accumulate.handle_host_call(
        host_call_id,
        %{gas: gas_remaining, registers: registers_struct, memory_ref: mem_ref},
        st.ctx_pair,
        st.n0_,
        st.operands,
        st.timeslot,
        st.service_index
      )

    #  the small gas math below is due to a differnt gas model between the inner vm and the host call
    #  the host calls simply start from some gas amount and deduct from it
    #  the inner vm keeps track of inital gas and spent gas (becuase gas is u64 but :out_of_gas exit is triggerd when gas < 0, u64 cannot be negative)

    gas_consumed = gas_remaining - post_host_call_state.gas
    spent_gas = state.spent_gas + gas_consumed

    #  we could be lazy and pass this back to the inner vm and get the final result there (for all cases except :continue)
    # but this would cost  two more extra NIF boundary crossing (encode/ decode /message send) => so we do it here

    case exit_reason do
      :out_of_gas ->
        send(st.parent, {spent_gas, :out_of_gas, new_ctx_pair})
        {:stop, :normal, st}

      :halt ->
        start_addr = elem(post_host_call_state.registers.r, 7)
        length = elem(post_host_call_state.registers.r, 8)

        result =
          case memory_read(mem_ref, start_addr, length) do
            {:ok, data} ->
              {spent_gas, data, new_ctx_pair}

            {:error, _error} ->
              {spent_gas, <<>>, new_ctx_pair}
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
        {:noreply, %{st | ctx_pair: new_ctx_pair}}

      _ ->
        send(st.parent, {spent_gas, :panic, st.ctx_pair})
        {:stop, :normal, st}
    end
  end

  #  resume_vm is seperated like this so we can upadte the genserver state with the post host call context BEOFRE
  #  resuming the inner vm execution
  # if we hadn't done this, there would be a race condition where an next ecall message could of come in before the genserver state was updated
  def handle_info({:resume_vm, mem_ref, updated_state, context_token}, st) do
    case resume(updated_state, mem_ref, context_token) do
      %ExecuteResult{output: :waiting, context_token: _token} ->
        {:noreply, st}

      %ExecuteResult{} = final ->
        send(st.parent, {final.used_gas, final.output, st.ctx_pair})
        {:stop, :normal, st}
    end
  end

  # Handle any unexpected messages
  def handle_info(msg, st) do
    {:noreply, st}
  end
end
