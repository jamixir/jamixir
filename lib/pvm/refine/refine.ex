defmodule PVM.Refine do
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkItem, WorkPackage}
  alias PVM.Refine.Executor
  alias PVM.{Host.General, Host.Refine}
  alias PVM.Host.General.FetchArgs
  alias PVM.Refine.RefineParams
  alias System.State.ServiceAccount
  alias Util.Hash
  import PVM.Constants.{HostCallResult, HostCallId}
  import PVM.Host.Gas
  import PVM.Types
  import Codec.Encoder

  @doc """
  ΨR: The Refine pvm invocation function.
  # Formula (B.5) v0.7.2
  """

  # see here about where the preimages comes from , it is not in the GP
  # but knowledge of it is assume,
  # this is a repeating pattern in refine logic (in-core, off-chain)
  # it is up to us to figure out what data/maps we are to store and where/when to store it
  # https://matrix.to/#/!ddsEwXlCWnreEGuqXZ:polkadot.io/$2BY5KB1iDMI3RxikTBLj0iMYJbf7L5EhZjXl0xRKlBw?via=polkadot.io&via=matrix.org&via=parity.io
  @spec execute(
          non_neg_integer(),
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
        core,
        work_item_index,
        work_package,
        authorizer_trace,
        import_segments,
        export_segment_offset,
        services,
        extrinsics
      ) do
    work_item = Enum.at(work_package.work_items, work_item_index)
    %WorkItem{service: service_id, code_hash: wc, payload: wy, refine_gas_limit: wg} = work_item
    px = work_package.context

    with {:ok, service} <- fetch_service(services, service_id),
         {:ok, program} <- fetch_code(service, px.timeslot, wc),
         :ok <- validate_code_size(program) do
      # let a = E(c,i,w_s,↕w_y,H(p))
      args = e({core, work_item_index, service_id, vs(wy), h(e(work_package))})

      Executor.run(
        program,
        %Refine.Context{},
        args,
        wg,
        %RefineParams{
          work_package: work_package,
          work_item_index: work_item_index,
          authorizer_trace: authorizer_trace,
          import_segments: import_segments,
          export_segment_offset: export_segment_offset,
          extrinsics: extrinsics,
          services: services,
          service_id: service_id
        }
      )
    else
      {:error, :service_not_found} -> {:bad, [], 0}
      {:error, :invalid_lookup} -> {:bad, [], 0}
      {:error, :code_too_large} -> {:big, [], 0}
    end
  end

  def handle_host_call(
        host_call_id,
        %{gas: gas, registers: registers, memory_ref: memory_ref},
        context,
        %RefineParams{
          work_package: wp,
          work_item_index: work_item_index,
          authorizer_trace: authorizer_trace,
          import_segments: import_segments,
          extrinsics: extrinsics,
          export_segment_offset: export_segment_offset,
          services: services,
          service_id: service_id
        }
      ) do
    host_call_result =
      case host(host_call_id) do
        :gas ->
          General.gas(gas, registers, memory_ref, context)

        :fetch ->
          General.fetch(%FetchArgs{
            gas: gas,
            registers: registers,
            memory_ref: memory_ref,
            work_package: wp,
            n: Hash.zero(),
            authorizer_trace: authorizer_trace,
            index: work_item_index,
            import_segments: import_segments,
            extrinsics: extrinsics,
            accumulation_inputs: nil,
            transfers: nil,
            context: context
          })

        :historical_lookup ->
          Refine.historical_lookup(
            gas,
            registers,
            memory_ref,
            context,
            service_id,
            services,
            wp.context.timeslot
          )

        :export ->
          Refine.export(gas, registers, memory_ref, context, export_segment_offset)

        :machine ->
          Refine.machine(gas, registers, memory_ref, context)

        :peek ->
          Refine.peek(gas, registers, memory_ref, context)

        :pages ->
          Refine.pages(gas, registers, memory_ref, context)

        :poke ->
          Refine.poke(gas, registers, memory_ref, context)

        :invoke ->
          Refine.invoke(gas, registers, memory_ref, context)

        :expunge ->
          Refine.expunge(gas, registers, memory_ref, context)

        :log ->
          General.log(gas, registers, memory_ref, context, work_item_index, service_id)

        _ ->
          g_ = gas - default_gas()

          %Refine.Result{
            exit_reason: if(g_ < 0, do: :out_of_gas, else: :continue),
            gas: gas - default_gas(),
            registers: %{registers | r: put_elem(registers.r, 7, what())},
            context: context
          }
      end

    %{exit_reason: exit_reason, gas: gas, registers: registers, context: context} =
      host_call_result

    {exit_reason, %{gas: gas, registers: registers}, context}
  end

  defp fetch_service(services, service_id) do
    if Map.has_key?(services, service_id) do
      {:ok, Map.get(services, service_id)}
    else
      {:error, :service_not_found}
    end
  end

  defp fetch_code(service, timeslot, code_hash) do
    case ServiceAccount.code_lookup(service, timeslot, code_hash) do
      nil -> {:error, :invalid_lookup}
      code -> {:ok, code}
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
