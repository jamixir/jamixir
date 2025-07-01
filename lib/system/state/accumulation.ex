defmodule System.State.Accumulation do
  @moduledoc """
  Chapter 12 - accumulation
  """

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
  use MapUnion
  use AccessStruct
  import Codec.Encoder
  import Utils

  @type extra_args :: %{timeslot_: non_neg_integer(), n0_: Types.hash()}
  @callback do_single_accumulation(
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

    # W∗
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
    {n, e_, deferred_transfers, accumulation_outputs, u} =
      sequential_accumulation(
        gas_limit,
        accumulatable_reports,
        initial_state,
        privileged_services.always_accumulated,
        extra_args
      )

    # Formula (12.25) v0.7.0
    %__MODULE__{
      services: services_intermediate,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_,
      manager: manager_,
      assigners: assigners_,
      delegator: delegator_,
      always_accumulated: always_accumulated_
    } = e_

    w_star_n = Enum.take(accumulatable_reports, n)

    # Formula (12.27) v0.7.0
    accumulation_stats = accumulate_statistics(w_star_n, u)

    # Formula (12.31) v0.7.0
    {services_intermediate_2, deferred_transfers_stats} =
      apply_transfers(
        services_intermediate,
        deferred_transfers,
        timeslot_,
        MapSet.new(Map.keys(accumulation_stats)),
        extra_args
      )

    # Formula (12.35) v0.7.0
    work_package_hashes = WorkReport.work_package_hashes(w_star_n)
    # Formula (12.36) v0.7.0
    accumulation_history_ = Enum.drop(accumulation_history, 1) ++ [work_package_hashes]
    {_, w_q} = WorkReport.separate_work_reports(work_reports, accumulation_history)
    # Formula (12.37) v0.7.0
    ready_to_accumulate_ =
      build_ready_to_accumulate_(
        ready_to_accumulate,
        work_package_hashes,
        w_q,
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
      accumulation_outputs: accumulation_outputs,
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
          %{non_neg_integer() => non_neg_integer()},
          extra_args()
        ) ::
          {non_neg_integer(), t(), list(DeferredTransfer.t()), list(AccumulationOutput.t()),
           list({Types.service_index(), Types.gas()})}

  def sequential_accumulation(
        gas_limit,
        work_reports,
        acc_state,
        always_accumulated,
        extra_args
      ) do
    i = number_of_work_reports_to_accumumulate(work_reports, gas_limit)

    if i == 0 do
      {0, acc_state, [], [], []}
    else
      {e_star, t_star, b_star, u_star} =
        parallelized_accumulation(
          acc_state,
          Enum.take(work_reports, i),
          always_accumulated,
          extra_args
        )

      g_star = Enum.sum(for {_, g} <- u_star, do: g)

      {j, e_prime, t, b, u} =
        sequential_accumulation(
          gas_limit - g_star,
          Enum.drop(work_reports, i),
          e_star,
          Map.new(),
          extra_args
        )

      {i + j, e_prime, t_star ++ t, b_star ++ b, u_star ++ u}
    end
  end

  @spec number_of_work_reports_to_accumumulate(list(WorkReport.t()), non_neg_integer()) ::
          non_neg_integer()
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
          %{non_neg_integer() => non_neg_integer()},
          extra_args()
        ) ::
          {t(), list(DeferredTransfer.t()), list(AccumulationOutput.t()),
           list({Types.service_index(), Types.gas()})}
  def parallelized_accumulation(acc_state, work_reports, always_accumulated, extra_args) do
    # s = {rs | w ∈ w, r ∈ wr} ∪ K(f)
    services = collect_services(work_reports, always_accumulated)

    # Pre-calculate all single accumulations for caching
    all_relevant_services =
      services
      |> MapSet.union(
        MapSet.new([acc_state.manager] ++ acc_state.assigners ++ [acc_state.delegator])
      )

    accumulation_cache =
      build_accumulation_cache(
        all_relevant_services,
        acc_state,
        work_reports,
        always_accumulated,
        extra_args
      )

    cached_accumulation = fn service_id ->
      case Map.get(accumulation_cache, service_id) do
        nil ->
          single_accumulation(
            acc_state,
            work_reports,
            always_accumulated,
            service_id,
            extra_args
          )

        result ->
          result
      end
    end

    # u = [(s, Δ₁(o, w, f, s)u) | s ∈ s]
    gas_used = for s <- services, do: {s, cached_accumulation.(s).gas_used}

    # b = {(s, b) | s ∈ s, b = Δ₁(o, w, f, s)b, b ≠ ∅}
    accumulation_outputs =
      for s <- services,
          accumulation_result = cached_accumulation.(s),
          is_binary(accumulation_result.output),
          do: %AccumulationOutput{service: s, accumulated_output: accumulation_result.output}

    # t = [Δ₁(o, w, f, s)t | s ∈ s] (flattened transfers)
    transfers =
      Enum.flat_map(services, fn s ->
        accumulation_result = cached_accumulation.(s)
        accumulation_result.transfers
      end)

    original_services = acc_state.services

    # n = ⋃({(Δ₁(o, w, f, s)o)d \ K(d ∖ {s})})
    # - The post-accumulation state for service s (the accumulating service)
    # - but not in the original state (excluding the accumulating service itself)
    # aka newly created services + accumulating service
    newly_created_services =
      Enum.reduce(services, %{}, fn accumulating_service, acc_n ->
        post_accumulation_services = cached_accumulation.(accumulating_service).state.services

        original_keys_excluding_s = Map.keys(Map.delete(original_services, accumulating_service))

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
        post_accumulation_services = cached_accumulation.(accumulating_service).state.services

        original_keys = keys_set(original_services)
        post_accumulation_keys = keys_set(post_accumulation_services)

        # keys that are present in the original state but not in the post-accumulation state => removed services
        removed_keys_by_accumulating_service =
          MapSet.difference(original_keys, post_accumulation_keys)

        # Union with accumulator
        MapSet.union(acc_m, removed_keys_by_accumulating_service)
      end)

    # Calculate preimages for d'
    service_preimages =
      for s <- services,
          accumulation_result = cached_accumulation.(s),
          do:
            accumulation_result.preimages
            |> List.flatten()

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

    %AccumulationResult{state: state_star_manager} = cached_accumulation.(acc_state.manager)

    %{
      manager: manager_,
      assigners: a_star,
      delegator: v_star,
      always_accumulated: always_accumulated_
    } = state_star_manager

    # ∀c ∈ NC : a'c = ((Δ₁(o, w, f, a*c)o)a)c
    assigners_ =
      for {a_c_star, core_index} <- Enum.with_index(a_star) do
        a_c_accumulation =
          single_accumulation(
            state_star_manager,
            work_reports,
            always_accumulated,
            a_c_star,
            extra_args
          )

        Enum.at(a_c_accumulation.state.assigners, core_index)
      end

    # v' = (Δ₁(o, w, f, v*)o)v
    delegator_ =
      single_accumulation(
        state_star_manager,
        work_reports,
        always_accumulated,
        v_star,
        extra_args
      ).state.delegator

    # i' = (Δ₁(o, w, f, v)o)i
    next_validators_ = cached_accumulation.(acc_state.delegator).state.next_validators

    # ∀c ∈ NC : q'c = (Δ₁(o, w, f, ac)o)_q_c
    authorizer_queue_ =
      for {a_c, core_index} <- Enum.with_index(acc_state.assigners) do
        a_c_accumulation = cached_accumulation.(a_c)
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

    {accumulation_state, transfers, accumulation_outputs, gas_used}
  end

  defp build_accumulation_cache(
         all_services,
         acc_state,
         work_reports,
         always_accumulated,
         extra_args
       ) do
    tasks =
      Enum.map(all_services, fn service_id ->
        Task.async(fn ->
          result =
            single_accumulation(
              acc_state,
              work_reports,
              always_accumulated,
              service_id,
              extra_args
            )

          {service_id, result}
        end)
      end)

    Enum.reduce(tasks, %{}, fn task, cache ->
      {service_id, result} = Task.await(task)
      Map.put(cache, service_id, result)
    end)
  end

  # Formula (12.18) v0.7.0
  @spec integrate_preimages(
          %{Types.service_index() => ServiceAccount.t()},
          list({Types.service_index(), binary()}),
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

  # Formula (12.20) v0.6.5
  def single_accumulation(acc_state, work_reports, service_dict, service, extra_args) do
    module = Application.get_env(:jamixir, :accumulation_module, __MODULE__)

    module.do_single_accumulation(
      acc_state,
      work_reports,
      service_dict,
      service,
      extra_args
    )
  end

  def do_single_accumulation(
        acc_state,
        work_reports,
        service_dict,
        service,
        %{timeslot_: timeslot_, n0_: n0_}
      ) do
    {gas, operands} = pre_single_accumulation(work_reports, service_dict, service)

    PVM.accumulate(acc_state, timeslot_, service, gas, operands, %{n0_: n0_})
    |> AccumulationResult.new()
  end

  def pre_single_accumulation(work_reports, service_dict, service) do
    initial_g = Map.get(service_dict, service, 0)

    service_results =
      for %WorkReport{digests: wd, output: wt, specification: ws, authorizer_hash: wa} <-
            work_reports,
          %WorkDigest{service: ^service, gas_ratio: rg, result: rl, payload_hash: ry} <- wd,
          do: {rg, rl, ry, wt, ws, wa}

    total_gas =
      initial_g +
        Enum.sum(Stream.map(service_results, &elem(&1, 0)))

    operands =
      for {rg, rl, ry, wt, ws, wa} <- service_results do
        %Accumulate.Operand{
          package_hash: ws.work_package_hash,
          segment_root: ws.exports_root,
          authorizer: wa,
          output: wt,
          payload_hash: ry,
          data: rl,
          gas_limit: rg
        }
      end

    {total_gas, operands}
  end

  # Formula (12.28) v0.6.7
  # Formula (12.29) v0.6.7
  # Formula (12.30) v0.6.7
  # Formula (12.31) v0.6.7
  # Formula (12.32) v0.6.7

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
        # Formula (12.27) v0.6.7
        selected_transfers = DeferredTransfer.select_transfers_for_destination(transfers, s)
        transfer_count = length(selected_transfers)

        # Formula (12.28) v0.6.7
        {service_with_transfers_applied, used_gas} =
          PVM.on_transfer(services_intermediate, timeslot_, s, selected_transfers, extra_args)

        # Formula (12.29) v0.6.7
        # Formula (12.30) v0.6.7
        service_with_transfers_applied_ =
          if s in accumulates_service_keys,
            do: %{service_with_transfers_applied | last_accumulation_slot: timeslot_},
            else: service_with_transfers_applied

        updated_services_acc = Map.put(services_acc, s, service_with_transfers_applied_)

        # Formula (12.32) v0.6.7
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
