defmodule PVM.Host.General do
  alias System.State.ServiceAccount
  import PVM.Host.Gas
  import PVM.Host.General.Internal
  alias PVM.Host.General
  alias PVM.Host.General.FetchArgs
  import PVM.Host.GasHandler

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  def gas(gas, registers, _memory_ref, context, _args \\ []) do
    {exit_reason, remaining_gas} = check_gas(gas)

    result = %General.Result{
      exit_reason: exit_reason,
      gas: remaining_gas,
      registers: registers,
      context: context
    }

    if exit_reason == :continue do
      registers_ = %{registers | r: put_elem(registers.r, 7, remaining_gas)}
      %{result | registers: registers_}
    else
      result
    end
  end

  # ΩY (ϱ, ω, µ, (m, e), p, n, r, i, i, x, o, t)
  @spec fetch(FetchArgs.t()) :: General.Result.t()
  def fetch(%FetchArgs{} = args) do
    with_gas(
      General.Result,
      {args.gas, args.registers, args.memory_ref, args.context},
      &fetch_internal/10,
      [
        args.work_package,
        args.n,
        args.authorizer_trace,
        args.index,
        args.import_segments,
        args.preimages,
        args.operands
      ]
    )
  end

  def lookup(gas, registers, memory_ref, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory_ref, context},
      &lookup_internal/5,
      [service_index, services]
    )
  end

  def read(gas, registers, memory_ref, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory_ref, context},
      &read_internal/5,
      [service_index, services]
    )
  end

  def write(gas, registers, memory_ref, context, service_index) do
    with_gas(
      General.Result,
      {gas, registers, memory_ref, context},
      &write_internal/4,
      [service_index]
    )
  end

  def info(gas, registers, memory_ref, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory_ref, context},
      &info_internal/5,
      [service_index, services]
    )
  end

  def log(gas, registers, memory_ref, context, core_index \\ nil, service_index \\ nil) do
    with_gas(
      General.Result,
      {gas, registers, memory_ref, context},
      &log_internal/5,
      [core_index, service_index],
      0
    )
  end
end
