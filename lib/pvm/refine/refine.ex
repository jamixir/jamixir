defmodule PVM.Refine do
  alias Util.Hash
  alias PVM.Registers
  alias System.State.ServiceAccount
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkPackage, WorkItem}
  alias PVM.{ArgInvoc, Host.Refine, Host.General}
  alias PVM.Host.General.FetchArgs
  import PVM.Constants.{HostCallResult, HostCallId}
  import PVM.Host.Gas
  import PVM.Types
  import Codec.Encoder

  @doc """
  ΨR: The Refine pvm invocation function.
  # Formula (B.5) v0.7.0
  """

  # see here about where the preimages comes from , it is not in the GP
  # but knowledge of it is assume,
  # this is a repeating pattern in refine logic (in-core, off-chain)
  # it is up to us to figure out what data/maps we are to store and where/when to store it
  # https://matrix.to/#/!ddsEwXlCWnreEGuqXZ:polkadot.io/$2BY5KB1iDMI3RxikTBLj0iMYJbf7L5EhZjXl0xRKlBw?via=polkadot.io&via=matrix.org&via=parity.io
  @spec execute(
          non_neg_integer(),
          WorkPackage.t(),
          binary(),
          list(list(binary())),
          non_neg_integer(),
          %{integer() => ServiceAccount.t()},
          %{{Types.hash(), non_neg_integer()} => binary()}
        ) ::
          {binary() | WorkExecutionError.t(), list(binary()), Types.gas()}
  def execute(
        work_item_index,
        work_package,
        authorizer_trace,
        import_segments,
        export_segment_offset,
        services,
        # preimages needs to come from DA layer
        # and satisy: x = [[x S (H(x), SxS) <− wx] S w <− pw
        # https://graypaper.fluffylabs.dev/#/9a08063/2fd6002fd600?v=0.6.6
        preimages
      ) do
    work_item = Enum.at(work_package.work_items, work_item_index)
    %WorkItem{service: service_id, code_hash: wc, payload: wy, refine_gas_limit: wg} = work_item
    px = work_package.context

    with {:ok, service} <- fetch_service(services, service_id),
         {:ok, program} <- fetch_lookup(service, px.timeslot, wc),
         :ok <- validate_code_size(program) do
      f = fn n, %{gas: gas, registers: registers, memory: memory}, context ->
        host_call_result =
          case host(n) do
            :gas ->
              General.gas(gas, registers, memory, context)

            :fetch ->
              General.fetch(%FetchArgs{
                gas: gas,
                registers: registers,
                memory: memory,
                work_package: work_package,
                n: Hash.zero(),
                authorizer_trace: authorizer_trace,
                index: work_item_index,
                import_segments: import_segments,
                preimages: preimages,
                operands: nil,
                transfers: nil,
                context: context
              })

            :historical_lookup ->
              Refine.historical_lookup(
                gas,
                registers,
                memory,
                context,
                service_id,
                services,
                px.timeslot
              )

            :export ->
              Refine.export(gas, registers, memory, context, export_segment_offset)

            :machine ->
              Refine.machine(gas, registers, memory, context)

            :peek ->
              Refine.peek(gas, registers, memory, context)

            :pages ->
              Refine.pages(gas, registers, memory, context)

            :poke ->
              Refine.poke(gas, registers, memory, context)

            :invoke ->
              Refine.invoke(gas, registers, memory, context)

            :expunge ->
              Refine.expunge(gas, registers, memory, context)

            :log ->
              General.log(gas, registers, memory, context, work_item_index, service_id)

            _ ->
              %Refine.Result{
                exit_reason: :continue,
                gas: gas - default_gas(),
                registers: Registers.set(registers, 7, what()),
                memory: memory,
                context: context
              }
          end

        %{
          exit_reason: exit_reason,
          gas: gas,
          registers: registers,
          memory: memory,
          context: context
        } = host_call_result

        {exit_reason, %{gas: gas, registers: registers, memory: memory}, context}
      end

      args = e({work_item_index, service_id, vs(wy), h(e(work_package))})

      {gas, result, %Refine.Context{e: exports}} =
        ArgInvoc.execute(program, 0, wg, args, f, %Refine.Context{})

      if result in [:out_of_gas, :panic] do
        {result, [], gas}
      else
        {result, exports, gas}
      end
    else
      {:error, :service_not_found} -> {:bad, [], 0}
      {:error, :invalid_lookup} -> {:bad, [], 0}
      {:error, :code_too_large} -> {:big, [], 0}
    end
  end

  defp fetch_service(services, service_id) do
    if Map.has_key?(services, service_id) do
      {:ok, Map.get(services, service_id)}
    else
      {:error, :service_not_found}
    end
  end

  defp fetch_lookup(service, timeslot, code) do
    case ServiceAccount.historical_lookup(service, timeslot, code) do
      nil -> {:error, :invalid_lookup}
      lookup -> {:ok, lookup}
    end
  end

  defp validate_code_size(lookup) do
    if byte_size(lookup) <= Constants.max_service_code_size() do
      :ok
    else
      {:error, :code_too_large}
    end
  end
end
