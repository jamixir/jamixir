defmodule PVM.Host.General do
  alias System.DeferredTransfer
  alias PVM.Accumulate.Operand
  alias Block.Extrinsic.WorkPackage
  alias PVM.Memory
  alias PVM.Host.General
  alias System.State.ServiceAccount
  alias PVM.Registers
  import PVM.Host.Gas
  import PVM.Host.General.Internal
  import PVM.Host.GasHandler

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  def gas(gas, registers, memory, context, _args \\ []) do
    {exit_reason, remaining_gas} = check_gas(gas)

    result = %General.Result{
      exit_reason: exit_reason,
      gas: remaining_gas,
      registers: registers,
      memory: memory,
      context: context
    }

    if exit_reason == :continue do
      registers_ = Registers.set(registers, :r7, remaining_gas)
      %{result | registers: registers_}
    else
      result
    end
  end

  # ΩY (ϱ, ω, µ, (m, e), p, n, r, i, i, x, o, t)
  @spec fetch(
          non_neg_integer(),
          Registers,
          Memory,
          # fetch in (0.6.6) does not use the context, so for now i am leaving the type unspecifed
          any(),
          WorkPackage,
          binary(),
          any(),
          non_neg_integer(),
          list(list(binary())),
          list(list({Types.hash(), non_neg_integer()})),
          list(Operand.t()),
          list(DeferredTransfer.t())
        ) ::
          nil
  def fetch(
        gas,
        registers,
        memory,
        context,
        work_package,
        n,
        authorizer_output,
        service_index,
        import_segments,
        extrinsics,
        operands,
        transfers
      ) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &fetch_internal/11,
      [work_package, n, authorizer_output, service_index, import_segments, extrinsics, operands, transfers]
    )
  end

  def lookup(gas, registers, memory, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &lookup_internal/5,
      [service_index, services]
    )
  end

  def read(gas, registers, memory, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &read_internal/5,
      [service_index, services]
    )
  end

  def write(gas, registers, memory, context, service_index) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &write_internal/4,
      [service_index]
    )
  end

  def info(gas, registers, memory, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &info_internal/5,
      [service_index, services]
    )
  end
end
