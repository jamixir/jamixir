defmodule System.State.Accumulation do
  @moduledoc """
  Chapter 12 - accumulation
  """

  alias Util.Collections
  alias Block.Extrinsic.Guarantee.{WorkDigest, WorkReport}
  alias PVM.Accumulate
  alias System.{AccumulationResult, DeferredTransfer, State}

  alias System.State.{
    PrivilegedServices,
    Ready,
    ServiceAccount,
    Validator,
    RecentHistory.AccumulationOutput
  }

  alias Types
  import Util.Hex, only: [b16: 1]
  use MapUnion
  use AccessStruct
  import Codec.Encoder
  import Utils
  require Logger

  @type extra_args :: %{timeslot_: non_neg_integer(), n0_: Types.hash()}
  # Formula (12.15) v0.7.0
  @type used_gas :: {Types.service_index(), Types.gas()}
  @callback single_accumulation(
              t(),
              list(),
              map(),
              non_neg_integer(),
              extra_args()
            ) ::
              AccumulationResult.t()
  @callback do_transition(list(), State.t(), extra_args()) :: any()

  # Formula (12.13) v0.7.0 - S
  @type t :: %__MODULE__{
          # d: Service accounts state (δ)
          services: %{non_neg_integer() => ServiceAccount.t()},
          # i: Upcoming validator keys (ι)
          next_validators: list(Validator.t()),
          # q: Queue of work-reports (φ)
          authorizer_queue: list(list(Types.hash())),
          # m: Manager service
          manager: non_neg_integer(),
          # a: Assigners
          assigners: list(non_neg_integer()),
          # v: Delegator
          delegator: non_neg_integer(),
          # z: Always accers
          always_accumulated: %{non_neg_integer() => non_neg_integer()}
        }

  defstruct services: %{},
            next_validators: [],
            authorizer_queue: [[]],
            manager: 0,
            assigners: [],
            delegator: 0,
            always_accumulated: %{}

  def transition(w, t_, n0_, s) do
    module = Application.get_env(:jamixir, :accumulation, __MODULE__)
    module.do_transition(w, s, %{timeslot_: t_, n0_: n0_})
  end

  def do_transition(
        work_reports,
        %State{
          accumulation_history: accumulation_history,
          ready_to_accumulate: ready_to_accumulate,
          privileged_services: privileged_services,
          next_validators: next_validators,
          authorizer_queue: authorizer_queue,
          services: services,
          timeslot: timeslot
        },
        %{timeslot_: timeslot_} = extra_args
      ) do
    # Formula (12.22) v0.7.0
    gas_limit =
      max(
        Constants.gas_total_accumulation(),
        Constants.gas_accumulation() * Constants.core_count() +
          Enum.sum(Map.values(privileged_services.always_accumulated))
      )

    # R∗
    accumulatable_reports =
      WorkReport.accumulatable_work_reports(
        work_reports,
        timeslot_,
        accumulation_history,
        ready_to_accumulate
      )

    # Formula (12.23) v0.7.0
    # e = (d: δ,i: ι,q: ϕ,m: χ_M ,a: χ_A,v: χ_V ,z: χ_Z)
    initial_state = %__MODULE__{
      services: services,
      next_validators: next_validators,
      authorizer_queue: authorizer_queue,
      manager: privileged_services.manager,
      assigners: privileged_services.assigners,
      delegator: privileged_services.delegator,
      always_accumulated: privileged_services.always_accumulated
    }

    # Formula (12.24) v0.7.0
    {number_of_accumulated_work_reports, acc_state_, deferred_transfers, accumulation_outputs_,
     used_gas} =
      sequential_accumulation(
        gas_limit,
        accumulatable_reports,
        initial_state,
        privileged_services.always_accumulated,
        extra_args
      )

    # Formula (12.25) v0.7.3
    accumulation_outputs_ = Enum.sort_by(accumulation_outputs_, & &1.service)

    # Formula (12.25) v0.7.0
    %__MODULE__{
      services: services_intermediate,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_,
      manager: manager_,
      assigners: assigners_,
      delegator: delegator_,
      always_accumulated: always_accumulated_
    } = acc_state_

    # R∗...n
    accumulated_reports = Enum.take(accumulatable_reports, number_of_accumulated_work_reports)

    # Formula (12.26) v0.7.0
    # Formula (12.27) v0.7.0
    accumulation_stats = accumulate_statistics(accumulated_reports, used_gas)

    # Formula (12.31) v0.7.0
    # Formula (12.33) v0.7.0
    {services_intermediate_2, deferred_transfers_stats} =
      apply_transfers(
        services_intermediate,
        deferred_transfers,
        timeslot_,
        MapSet.new(Map.keys(accumulation_stats)),
        extra_args
      )

    # Formula (12.35) v0.7.0
    work_package_hashes = WorkReport.work_package_hashes(accumulated_reports)
    # Formula (12.36) v0.7.0
    accumulation_history_ = Enum.drop(accumulation_history, 1) ++ [work_package_hashes]
    {_, r_q} = WorkReport.separate_work_reports(work_reports, accumulation_history)
    # Formula (12.37) v0.7.0
    ready_to_accumulate_ =
      build_ready_to_accumulate_(
        ready_to_accumulate,
        work_package_hashes,
        r_q,
        timeslot_,
        timeslot
      )

    privileged_services_ = %PrivilegedServices{
      manager: manager_,
      assigners: assigners_,
      delegator: delegator_,
      always_accumulated: always_accumulated_
    }

    %{
      services: services_intermediate_2,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_,
      ready_to_accumulate: ready_to_accumulate_,
      privileged_services: privileged_services_,
      accumulation_history: accumulation_history_,
      accumulation_outputs: accumulation_outputs_,
      accumulation_stats: accumulation_stats,
      deferred_transfers_stats: deferred_transfers_stats
    }
  end

  # Formula (12.26) v0.7.0
  # Formula (12.27) v0.7.0
  # Formula (12.28) v0.7.0
  def accumulate_statistics(work_reports, service_gas_used) do
    gas_per_service =
      for {s, u} <- service_gas_used, reduce: %{} do
        stat ->
          case Map.get(stat, s) do
            nil -> Map.put(stat, s, u)
            gas -> Map.put(stat, s, gas + u)
          end
      end

    for r <- work_reports, d <- r.digests, reduce: %{} do
      stat ->
        case Map.get(stat, d.service) do
          nil -> Map.put(stat, d.service, {1, Map.get(gas_per_service, d.service, 0)})
          {count, total_gas} -> Map.put(stat, d.service, {count + 1, total_gas})
        end
    end
  end

  # Formula (12.16) v0.7.0
  @spec sequential_accumulation(
          non_neg_integer(),
          list(WorkReport.t()),
          t(),
          PrivilegedServices.free_accumulating_services(),
          extra_args()
        ) ::
          {non_neg_integer(), t(), list(DeferredTransfer.t()), list(AccumulationOutput.t()),
           list(used_gas())}

  def sequential_accumulation(
        gas_limit,
        work_reports,
        acc_state,
        always_accumulated_services,
        extra_args
      ) do
    total_work_reports = length(work_reports)

    counter = next_counter()

    Logger.debug("=== Sequential Accumulation ##{counter} START ===")

    if total_work_reports > 0 do
      all_hashes =
        work_reports |> Enum.map(&b16(&1.specification.work_package_hash)) |> Enum.join(", ")

      Logger.debug("Work packages (#{total_work_reports}): #{all_hashes}")
    end

    result =
      sequential_accumulation_recursive(
        gas_limit,
        work_reports,
        acc_state,
        always_accumulated_services,
        extra_args,
        total_work_reports,
        # accumulated_so_far
        0,
        counter
      )

    Logger.debug("=== Sequential Accumulation ##{counter} END ===")
    result
  end

  defp next_counter() do
    key = {__MODULE__, :counter}

    current = :persistent_term.get(key, 0)
    next = current + 1
    :persistent_term.put(key, next)
    next
  end

  defp sequential_accumulation_recursive(
         gas_limit,
         work_reports,
         acc_state,
         always_accumulated_services,
         extra_args,
         total_work_reports,
         accumulated_so_far,
         seq_counter
       ) do
    i = number_of_work_reports_to_accumumulate(work_reports, gas_limit)
    total_count = length(work_reports)

    if i == 0 do
      # Log remaining work reports
      if total_count > 0 and Logger.level() == :debug do
        remaining_info =
          Enum.map_join(work_reports, ", ", fn wr ->
            services = wr.digests |> Enum.map(& &1.service) |> Enum.uniq() |> Enum.join(",")
            "#{b16(wr.specification.work_package_hash)}(#{services})"
          end)

        Logger.debug("Left unaccumulated (#{total_count}): #{remaining_info}")
      end

      {0, acc_state, [], [], []}
    else
      {current_batch, remaining_work_reports} = Enum.split(work_reports, i)

      if Logger.level() == :debug do
        hashes = work_reports |> Enum.map_join(", ", &b16(&1.specification.work_package_hash))

        Logger.debug("Gas limit: #{gas_limit}, can accumulate #{i}/#{total_count} (#{hashes})")

        current_info =
          Enum.map_join(current_batch, ", ", fn wr ->
            services = wr.digests |> Enum.map(& &1.service) |> Enum.uniq() |> Enum.join(",")
            "#{b16(wr.specification.work_package_hash)}(#{services})"
          end)

        Logger.debug("Accumulating (#{i}/#{total_count}): #{current_info}")
        Logger.debug(">>> Parallel Accumulation START")
      end

      {acc_state_star, transfers_star, accumulation_outputs_star, used_gas_star} =
        parallelized_accumulation(
          acc_state,
          current_batch,
          always_accumulated_services,
          extra_args
        )

      Logger.debug("<<< Parallel Accumulation END")

      consumed_gas = Enum.sum(for {_, g} <- used_gas_star, do: g)

      {number_of_accumulated_work_reports, acc_state_, transfers, accumulation_outputs, used_gas} =
        sequential_accumulation_recursive(
          gas_limit - consumed_gas,
          remaining_work_reports,
          acc_state_star,
          Map.new(),
          extra_args,
          total_work_reports,
          accumulated_so_far + i,
          seq_counter
        )

      {i + number_of_accumulated_work_reports, acc_state_, transfers_star ++ transfers,
       accumulation_outputs_star ++ accumulation_outputs, used_gas_star ++ used_gas}
    end
  end

  @spec number_of_work_reports_to_accumumulate(list(WorkReport.t()), non_neg_integer()) ::
          non_neg_integer()
  def number_of_work_reports_to_accumumulate([], _), do: 0

  def number_of_work_reports_to_accumumulate(work_reports, gas_limit) do
    Enum.reduce_while(1..length(work_reports), 0, fn i, _acc ->
      sum =
        Enum.sum(
          for d <- Enum.flat_map(Enum.take(work_reports, i), & &1.digests), do: d.gas_ratio
        )

      if sum <= gas_limit do
        {:cont, i}
      else
        {:halt, i - 1}
      end
    end)
  end

  # Formula (12.17) v0.7.0
  @spec parallelized_accumulation(
          t(),
          list(WorkReport.t()),
          PrivilegedServices.free_accumulating_services(),
          extra_args()
        ) ::
          {t(), list(DeferredTransfer.t()), list(AccumulationOutput.t()), list(used_gas())}
  def parallelized_accumulation(acc_state, work_reports, always_accumulated_services, extra_args) do
    accumulation_module = Application.get_env(:jamixir, :accumulation_module, __MODULE__)

    # s = {rs | w ∈ w, r ∈ wr} ∪ K(f)
    services = collect_services(work_reports, always_accumulated_services)

    available_services =
      MapSet.union(
        services,
        MapSet.new([acc_state.manager] ++ acc_state.assigners ++ [acc_state.delegator])
      )

    {:ok, cache_agent} =
      Agent.start_link(fn ->
        %{available: available_services, results: %{}}
      end)

    get_or_accumulate = fn service_id, state ->
      Agent.get_and_update(cache_agent, fn %{available: available, results: results} ->
        if service_id in available do
          result =
            accumulation_module.single_accumulation(
              state,
              work_reports,
              always_accumulated_services,
              service_id,
              extra_args
            )

          {result,
           %{
             available: MapSet.delete(available, service_id),
             results: Map.put(results, service_id, result)
           }}
        else
          {Map.get(results, service_id), %{available: available, results: results}}
        end
      end)
    end

    # u = [(s, Δ₁(o, w, f, s)u) | s ∈ s]
    gas_used = for s <- services, do: {s, get_or_accumulate.(s, acc_state).gas_used}

    # b = {(s, b) | s ∈ s, b = Δ₁(o, w, f, s)b, b ≠ ∅}
    accumulation_outputs =
      for s <- services,
          accumulation_result = get_or_accumulate.(s, acc_state),
          is_binary(accumulation_result.output),
          do: %AccumulationOutput{service: s, accumulated_output: accumulation_result.output}

    # t = [Δ₁(o, w, f, s)t | s ∈ s]  => concat all
    transfers =
      Enum.flat_map(services, &get_or_accumulate.(&1, acc_state).transfers)

    # d
    original_services = acc_state.services

    # n = ⋃({(Δ₁(o, w, f, s)o)d \ K(d ∖ {s})})
    # - The post-accumulation state for service s (the accumulating service)
    # - but not in the original state (excluding the accumulating service itself)
    # aka newly created services + accumulating service
    newly_created_services =
      Enum.reduce(services, %{}, fn accumulating_service, acc_n ->
        # ∆1(e, w, f , s)e)d
        post_accumulation_services =
          get_or_accumulate.(accumulating_service, acc_state).state.services

        # K(d ∖ { s })
        original_keys_excluding_s = Map.keys(Map.delete(original_services, accumulating_service))

        # Δ₁(o, w, f, s)o)d \ K(d ∖ {s})
        newly_created_services_by_accumulating_service =
          Map.drop(post_accumulation_services, original_keys_excluding_s)

        # Union with accumulator
        Map.merge(acc_n, newly_created_services_by_accumulating_service)
      end)

    # m = ⋃(K(d) ∖ K((Δ₁(o, w, f, s)o)d))
    # m collects service keys that are:
    # - Present in the original state
    # - But absent from the post-accumulation state
    # aka deleted services
    deleted_services =
      Enum.reduce(services, MapSet.new(), fn accumulating_service, acc_m ->
        # K(Δ₁(o, w, f, s)o)d)
        post_accumulation_keys =
          keys_set(get_or_accumulate.(accumulating_service, acc_state).state.services)

        # K(d)
        original_keys = keys_set(original_services)

        # keys that are present in the original state but not in the post-accumulation state => removed services
        # K(d) ∖ K((Δ₁(o, w, f, s)o)d)
        removed_keys_by_accumulating_service =
          MapSet.difference(original_keys, post_accumulation_keys)

        # Union with accumulator
        MapSet.union(acc_m, removed_keys_by_accumulating_service)
      end)

    # Calculate preimages for d'
    #  ⋃ Δ₁(o, w, f, s)p)
    service_preimages =
      for s <- services,
          accumulation_result = get_or_accumulate.(s, acc_state),
          reduce: MapSet.new() do
        acc -> MapSet.union(acc, accumulation_result.preimages)
      end

    # d' = P((d ∪ n) ∖ m, ⋃ Δ₁(o, w, f, s)p)
    # original services + newly created services + accumulating service
    all_services = Map.merge(original_services, newly_created_services)
    # without deleted services
    all_services_without_deleted_services =
      Map.drop(all_services, MapSet.to_list(deleted_services))

    services_ =
      integrate_preimages(
        all_services_without_deleted_services,
        service_preimages,
        extra_args.timeslot_
      )

    %AccumulationResult{state: state_star_manager} =
      get_or_accumulate.(acc_state.manager, acc_state)

    %{
      manager: manager_,
      assigners: a_star,
      delegator: v_star,
      always_accumulated: always_accumulated_
    } = state_star_manager

    Agent.update(cache_agent, fn %{available: available, results: results} ->
      new_services = MapSet.new(a_star ++ [v_star])
      # Only add services that don't already have cached results
      services_to_add = MapSet.difference(new_services, keys_set(results))
      new_available = MapSet.union(available, services_to_add)
      %{available: new_available, results: results}
    end)

    # ∀c ∈ NC : a'c = ((Δ₁(o, w, f, a*c)o)a)c
    assigners_ =
      for {a_c_star, core_index} <- Enum.with_index(a_star) do
        a_c_accumulation = get_or_accumulate.(a_c_star, state_star_manager)
        Enum.at(a_c_accumulation.state.assigners, core_index)
      end

    # v' = (Δ₁(o, w, f, v*)o)v
    delegator_ =
      get_or_accumulate.(v_star, state_star_manager).state.delegator

    # i' = (Δ₁(o, w, f, v)o)i
    next_validators_ = get_or_accumulate.(acc_state.delegator, acc_state).state.next_validators

    # ∀c ∈ NC : q'c = (Δ₁(o, w, f, ac)o)_q_c
    authorizer_queue_ =
      for {a_c, core_index} <- Enum.with_index(acc_state.assigners) do
        a_c_accumulation = get_or_accumulate.(a_c, acc_state)
        Enum.at(a_c_accumulation.state.authorizer_queue, core_index)
      end

    accumulation_state = %__MODULE__{
      services: services_,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_,
      manager: manager_,
      assigners: assigners_,
      delegator: delegator_,
      always_accumulated: always_accumulated_
    }

    Agent.stop(cache_agent)

    {accumulation_state, transfers, accumulation_outputs, gas_used}
  end

  # Formula (12.18) v0.7.0
  @spec integrate_preimages(
          %{Types.service_index() => ServiceAccount.t()},
          MapSet.t({Types.service_index(), binary()}),
          Types.timeslot()
        ) ::
          %{Types.service_index() => ServiceAccount.t()}
  def integrate_preimages(services, preimages, timeslot_) do
    for {service_index, preimage} <- preimages, reduce: services do
      acc ->
        case Map.get(acc, service_index) do
          nil ->
            acc

          %ServiceAccount{} = sa ->
            if get_in(sa, [:storage, {h(preimage), byte_size(preimage)}]) in [nil, []] do
              sa = put_in(sa, [:storage, {h(preimage), byte_size(preimage)}], [timeslot_])
              sa = put_in(sa, [:preimage_storage_p, h(preimage)], preimage)
              Map.put(acc, service_index, sa)
            else
              acc
            end
        end
    end
  end

  def collect_services(work_reports, always_accumulated) do
    for(
      d <- Enum.flat_map(work_reports, & &1.digests),
      do: d.service,
      into: MapSet.new()
    ) ++ keys_set(always_accumulated)
  end

  # Formula (12.21) v0.7.0
  def single_accumulation(
        acc_state,
        work_reports,
        always_accumulating_services,
        service,
        %{timeslot_: timeslot_, n0_: n0_}
      ) do
    {gas, operands} = pre_single_accumulation(work_reports, always_accumulating_services, service)

    Logger.debug(
      "Accumulating service #{service} with #{length(operands)} operands (gas: #{gas})"
    )

    PVM.accumulate(acc_state, timeslot_, service, gas, operands, %{n0_: n0_})
  end

  def pre_single_accumulation(work_reports, always_accumulating_services, service) do
    initial_g = Map.get(always_accumulating_services, service, 0)

    service_results =
      for %WorkReport{digests: wd, output: wt, specification: ws, authorizer_hash: wa} <-
            work_reports,
          %WorkDigest{service: ^service, gas_ratio: rg, result: rl, payload_hash: ry} <- wd,
          do: {rg, rl, ry, wt, ws, wa}

    total_gas =
      initial_g + Collections.sum_by(service_results, &elem(&1, 0))

    operands =
      for {rg, rl, ry, wt, ws, wa} <- service_results do
        %Accumulate.Operand{
          # l
          data: rl,
          # g
          gas_limit: rg,
          # y
          payload_hash: ry,
          # t
          output: wt,
          # e
          segment_root: ws.exports_root,
          # p
          package_hash: ws.work_package_hash,
          # a
          authorizer: wa
        }
      end

    {total_gas, operands}
  end

  # Formula (12.29) v0.7.0
  # Formula (12.30) v0.7.0
  # Formula (12.31) v0.7.0
  # Formula (12.32) v0.7.0

  @spec apply_transfers(
          services_intermediate :: %{non_neg_integer() => ServiceAccount.t()},
          transfers :: list(DeferredTransfer.t()),
          timeslot_ :: Types.timeslot(),
          accumulates_service_keys :: MapSet.t(non_neg_integer()),
          extra_args :: extra_args()
        ) ::
          {%{Types.service_index() => ServiceAccount.t()},
           %{Types.service_index() => {non_neg_integer(), Types.gas()}}}
  def apply_transfers(
        services_intermediate,
        transfers,
        timeslot_,
        accumulates_service_keys,
        extra_args
      ) do
    {services, transfer_stats} =
      Enum.reduce(Map.keys(services_intermediate), {%{}, %{}}, fn s,
                                                                  {services_acc,
                                                                   transfer_stats_acc} ->
        # Formula (12.29) v0.7.0
        selected_transfers = DeferredTransfer.select_transfers_for_destination(transfers, s)
        transfer_count = length(selected_transfers)

        # Formula (12.30) v0.7.0
        {service_with_transfers_applied, used_gas} =
          PVM.OnTransfer.execute(
            services_intermediate,
            timeslot_,
            s,
            selected_transfers,
            extra_args
          )

        # Formula (12.31) v0.7.0
        # Formula (12.32) v0.7.0
        service_with_transfers_applied_ =
          if s in accumulates_service_keys,
            do: %{service_with_transfers_applied | last_accumulation_slot: timeslot_},
            else: service_with_transfers_applied

        updated_services_acc = Map.put(services_acc, s, service_with_transfers_applied_)

        # Formula (12.33) v0.7.0
        # Formula (12.34) v0.7.0
        updated_transfer_stats_acc =
          if transfer_count > 0 do
            Map.put(transfer_stats_acc, s, {transfer_count, used_gas})
          else
            transfer_stats_acc
          end

        {updated_services_acc, updated_transfer_stats_acc}
      end)

    {services, transfer_stats}
  end

  # Formula (12.37) v0.7.0
  @spec build_ready_to_accumulate_(
          ready_to_accumulate :: list(list(Ready.t())),
          w_star :: MapSet.t(WorkReport.t()),
          w_q :: list({WorkReport.t(), MapSet.t(Types.hash())}),
          header_timeslot :: non_neg_integer(),
          state_timeslot :: non_neg_integer()
        ) :: list(list(Ready.t()))

  def build_ready_to_accumulate_(
        [],
        _w_star,
        _w_q,
        _header_timeslot,
        _state_timeslot
      ) do
    []
  end

  def build_ready_to_accumulate_(
        ready_to_accumulate,
        work_package_hashes,
        w_q,
        timeslot_,
        timeslot
      ) do
    e = length(ready_to_accumulate)
    m = Util.Time.epoch_phase(timeslot_)

    list =
      for i <- 0..(e - 1) do
        cond do
          i == 0 ->
            WorkReport.filter_and_update_dependencies(w_q, work_package_hashes)

          i < timeslot_ - timeslot ->
            []

          true ->
            WorkReport.filter_and_update_dependencies(
              Enum.at(ready_to_accumulate, rem(m - i, e)) |> Enum.map(&Ready.to_tuple/1),
              work_package_hashes
            )
        end
      end
      |> Enum.reverse()
      |> rotate(m + 1)

    for q <- list, do: for({w, d} <- q, do: %Ready{work_report: w, dependencies: d})
  end

  def rotate(list, m) when is_list(list) do
    len = length(list)
    m = rem(m, len)
    # Take last m elements and prepend to rest
    Enum.take(list, -m) ++ Enum.drop(list, -m)
  end
end
