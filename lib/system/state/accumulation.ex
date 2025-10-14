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
  # Formula (12.17) v0.7.2
  @type used_gas :: {Types.service_index(), Types.gas()}
  @callback single_accumulation(
              t(),
              list(DeferredTransfer.t()),
              list(),
              map(),
              non_neg_integer(),
              extra_args()
            ) ::
              AccumulationResult.t()
  @callback do_transition(list(), State.t(), extra_args()) :: any()

  # Formula (12.16) v0.7.2 - S
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
          delegator: Types.service_index(),
          # r: Registrar
          registrar: Types.service_index(),
          # z: Always accers
          always_accumulated: %{non_neg_integer() => non_neg_integer()}
        }

  defstruct services: %{},
            next_validators: [],
            authorizer_queue: [[]],
            manager: 0,
            assigners: [],
            delegator: 0,
            registrar: 0,
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
    # Formula (12.25) v0.7.2
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

    # Formula (12.25) v0.7.2
    # e = (d: δ, i: ι, q: ϕ, m: χ_M , a: χ_A, v: χ_V, r: χ_R, z: χ_Z)
    initial_state = %__MODULE__{
      services: services,
      next_validators: next_validators,
      authorizer_queue: authorizer_queue,
      manager: privileged_services.manager,
      assigners: privileged_services.assigners,
      delegator: privileged_services.delegator,
      registrar: privileged_services.registrar,
      always_accumulated: privileged_services.always_accumulated
    }

    # Formula (12.25) v0.7.2
    {number_of_accumulated_work_reports, acc_state_, accumulation_outputs_, used_gas} =
      sequential_accumulation(
        gas_limit,
        [],
        accumulatable_reports,
        initial_state,
        privileged_services.always_accumulated,
        extra_args
      )

    # Formula (12.26) v0.7.3
    accumulation_outputs_ = Enum.sort_by(accumulation_outputs_, & &1.service)

    # Formula (12.27) v0.7.2
    %__MODULE__{
      services: services_intermediate,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_,
      manager: manager_,
      assigners: assigners_,
      delegator: delegator_,
      registrar: registrar_,
      always_accumulated: always_accumulated_
    } = acc_state_

    # R∗...n
    accumulated_reports = Enum.take(accumulatable_reports, number_of_accumulated_work_reports)

    # Formula (12.28) v0.7.2
    # Formula (12.29) v0.7.2
    accumulation_stats = accumulate_statistics(accumulated_reports, used_gas)

    # Formula (12.30) v0.7.2
    services_intermediate_2 =
      apply_last_accumulation(
        services_intermediate,
        timeslot_,
        MapSet.new(Map.keys(accumulation_stats))
      )

    # Formula (12.32) v0.7.2
    work_package_hashes = WorkReport.work_package_hashes(accumulated_reports)
    # Formula (12.33) v0.7.2
    accumulation_history_ = Enum.drop(accumulation_history, 1) ++ [work_package_hashes]
    {_, r_q} = WorkReport.separate_work_reports(work_reports, accumulation_history)
    # Formula (12.34) v0.7.2
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
      registrar: registrar_,
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
      accumulation_stats: accumulation_stats
    }
  end

  # Formula (12.28) v0.7.2
  # Formula (12.29) v0.7.2
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

  # Formula (12.18) v0.7.2
  @spec sequential_accumulation(
          non_neg_integer(),
          list(DeferredTransfer.t()),
          list(WorkReport.t()),
          t(),
          PrivilegedServices.free_accumulating_services(),
          extra_args()
        ) ::
          {non_neg_integer(), t(), list(AccumulationOutput.t()), list(used_gas())}

  def sequential_accumulation(
        gas_limit,
        deferred_transfers,
        work_reports,
        acc_state,
        always_accumulated_services,
        extra_args
      ) do
    total_work_reports = length(work_reports)

    counter = next_counter()

    Logger.debug("=== Sequential Accumulation ##{counter} START ===")

    if total_work_reports > 0 and Logger.level() == :debug do
      all_hashes =
        work_reports |> Enum.map(&b16(&1.specification.work_package_hash)) |> Enum.join(", ")

      Logger.debug("Work packages (#{total_work_reports}): #{all_hashes}")
    end

    result =
      sequential_accumulation_recursive(
        gas_limit,
        deferred_transfers,
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
         deferred_transfers,
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

    n = i + length(deferred_transfers) + map_size(always_accumulated_services)

    if n == 0 do
      # Log remaining work reports
      if total_count > 0 and Logger.level() == :debug do
        remaining_info =
          Enum.map_join(work_reports, ", ", fn wr ->
            services = wr.digests |> Enum.map(& &1.service) |> Enum.uniq() |> Enum.join(",")
            "#{b16(wr.specification.work_package_hash)}(#{services})"
          end)

        Logger.debug("Left unaccumulated (#{total_count}): #{remaining_info}")
      end

      {0, acc_state, [], []}
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
          deferred_transfers,
          current_batch,
          always_accumulated_services,
          extra_args
        )

      Logger.debug("<<< Parallel Accumulation END")

      g_star = gas_limit + Enum.sum(for(d <- deferred_transfers, do: d.gas_limit))
      consumed_gas = Enum.sum(for {_, g} <- used_gas_star, do: g)

      {number_of_accumulated_work_reports, acc_state_, accumulation_outputs, used_gas} =
        sequential_accumulation_recursive(
          g_star - consumed_gas,
          transfers_star,
          remaining_work_reports,
          acc_state_star,
          Map.new(),
          extra_args,
          total_work_reports,
          accumulated_so_far + i,
          seq_counter
        )

      {i + number_of_accumulated_work_reports, acc_state_,
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

  # TODO
  # Formula (12.19) v0.7.2
  @spec parallelized_accumulation(
          t(),
          list(DeferredTransfer.t()),
          list(WorkReport.t()),
          PrivilegedServices.free_accumulating_services(),
          extra_args()
        ) ::
          {t(), list(DeferredTransfer.t()), list(AccumulationOutput.t()), list(used_gas())}
  def parallelized_accumulation(
        acc_state,
        deferred_transfers,
        work_reports,
        always_accumulated_services,
        extra_args
      ) do
    accumulation_module = Application.get_env(:jamixir, :accumulation_module, __MODULE__)

    # s = {d_s | r ∈ r, d ∈ r_d} ∪ K(f) ∪ {t_d ∣ t ∈ t}
    services = collect_services(work_reports, always_accumulated_services, deferred_transfers)

    available_services =
      services ++
        MapSet.new(
          [acc_state.manager, acc_state.delegator, acc_state.registrar] ++ acc_state.assigners
        )

    {:ok, cache_agent} =
      Agent.start_link(fn -> %{available: available_services, results: %{}} end)

    get_or_accumulate = fn service_id, state ->
      Agent.get_and_update(cache_agent, fn %{available: available, results: results} ->
        if service_id in available do
          # ∆(s) ≡ ∆1(e, t, r, f, s)
          result =
            accumulation_module.single_accumulation(
              state,
              deferred_transfers,
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

    # u = [(s, Δ(s)_u) | s ∈ s]
    gas_used = for s <- services, do: {s, get_or_accumulate.(s, acc_state).gas_used}

    # b = {(s, b) | s ∈ s, b = Δ(s)_y, b ≠ ∅}
    accumulation_outputs =
      for s <- services,
          accumulation_result = get_or_accumulate.(s, acc_state),
          is_binary(accumulation_result.output),
          do: %AccumulationOutput{service: s, accumulated_output: accumulation_result.output}

    # t' = [Δ(s)_t | s ∈ s] => concat all
    transfers_ = Enum.flat_map(services, &get_or_accumulate.(&1, acc_state).transfers)

    # (d,i,q,m,a,v,r,z) = e
    %{services: original_services, assigners: a, delegator: v, registrar: r} = acc_state

    # n = ⋃({(Δ(s)_e)_d \ K(d ∖ {s})})
    # - The post-accumulation state for service s (the accumulating service)
    # - but not in the original state (excluding the accumulating service itself)
    # aka newly created services + accumulating service
    newly_created_services =
      Enum.reduce(services, %{}, fn accumulating_service, acc_n ->
        # ∆1(s)_e)_d
        post_accumulation_services =
          get_or_accumulate.(accumulating_service, acc_state).state.services

        # K(d ∖ { s })
        original_keys_excluding_s = Map.keys(Map.delete(original_services, accumulating_service))

        # Δ(s)_e)_d \ K(d ∖ {s})
        newly_created_services_by_accumulating_service =
          Map.drop(post_accumulation_services, original_keys_excluding_s)

        # Union with accumulator
        Map.merge(acc_n, newly_created_services_by_accumulating_service)
      end)

    # m = ⋃(K(d) ∖ K((Δ(s)_e)_d))
    deleted_services =
      Enum.reduce(services, MapSet.new(), fn s, acc_m ->
        # keys that are present in the original state but not in the
        # post-accumulation state => removed services
        acc_m ++
          MapSet.difference(
            keys_set(original_services),
            keys_set(get_or_accumulate.(s, acc_state).state.services)
          )
      end)

    # ⋃(Δ(s)_p) Calculate preimages for d'
    service_preimages =
      for s <- services,
          accumulation_result = get_or_accumulate.(s, acc_state),
          reduce: MapSet.new() do
        acc -> MapSet.union(acc, accumulation_result.preimages)
      end

    # d' = I((d ∪ n) ∖ m, ⋃ Δ(s)_p)
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

    # e* = ∆(m)e
    e_star = get_or_accumulate.(acc_state.manager, acc_state).state

    # (m', z') = e∗_(m,z)
    %{manager: manager_, always_accumulated: always_accumulated_} = e_star

    Agent.update(cache_agent, fn %{available: available, results: results} ->
      new_services = MapSet.new([e_star.delegator] ++ e_star.assigners)
      # Only add services that don't already have cached results
      services_to_add = MapSet.difference(new_services, keys_set(results))
      new_available = MapSet.union(available, services_to_add)
      %{available: new_available, results: results}
    end)

    # ∀c ∈ N_C : a'c = R(a_c, (e∗_a)_c, ((∆(a_c)_e)_a)_c)
    assigners_ =
      for {a_c, c} <- Enum.with_index(a) do
        r(
          a_c,
          Enum.at(e_star.assigners, c),
          Enum.at(get_or_accumulate.(a_c, acc_state).state.assigners, c)
        )
      end

    # v' = R(v, e∗_v ,(∆(v)_e)_v )
    delegator_ = r(v, e_star.delegator, get_or_accumulate.(v, acc_state).state.delegator)

    # r' = R(r, e∗_r ,(∆(r)_e)_r )
    registrar_ = r(r, e_star.registrar, get_or_accumulate.(r, acc_state).state.registrar)

    # i' = (Δ(v)_e)_i
    next_validators_ = get_or_accumulate.(v, acc_state).state.next_validators

    # ∀c ∈ NC : q'c = ((Δ(a_c)e)_q)_c
    authorizer_queue_ =
      for {a_c, core_index} <- Enum.with_index(a) do
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
      registrar: registrar_,
      always_accumulated: always_accumulated_
    }

    Agent.stop(cache_agent)

    {accumulation_state, transfers_, accumulation_outputs, gas_used}
  end

  def r(o, a, b), do: if(a == o, do: b, else: a)

  # Formula (12.21) v0.7.2 - I:
  @spec integrate_preimages(
          %{Types.service_index() => ServiceAccount.t()},
          MapSet.t(Preimage.t()),
          Types.timeslot()
        ) ::
          %{Types.service_index() => ServiceAccount.t()}
  def integrate_preimages(services, preimages, timeslot_) do
    for %{blob: blob, service: s} <- preimages, reduce: services do
      acc ->
        case Map.get(acc, s) do
          # s ∈/ K(d)
          nil ->
            acc

          %ServiceAccount{} = sa ->
            hash = h(blob)

            if get_in(sa, [:storage, {hash, byte_size(blob)}]) in [nil, []] do
              sa = put_in(sa, [:storage, {hash, byte_size(blob)}], [timeslot_])
              sa = put_in(sa, [:preimage_storage_p, hash], blob)
              Map.put(acc, s, sa)
            else
              acc
            end
        end
    end
  end

  def collect_services(work_reports, always_accumulated, transfers) do
    for(
      d <- Enum.flat_map(work_reports, & &1.digests),
      do: d.service,
      into: MapSet.new()
    ) ++ keys_set(always_accumulated) ++ MapSet.new(for(t <- transfers, do: t.receiver))
  end

  # Formula (12.24) v0.7.2
  def single_accumulation(
        acc_state,
        deffered_transfers,
        work_reports,
        always_accumulating_services,
        service,
        %{timeslot_: timeslot_, n0_: n0_}
      ) do
    {gas, accumulation_inputs} =
      pre_single_accumulation(
        work_reports,
        deffered_transfers,
        always_accumulating_services,
        service
      )

    Logger.debug(
      "Accumulating service #{service} with #{length(accumulation_inputs)} accumulation_inputs (gas: #{gas})"
    )

    PVM.accumulate(acc_state, timeslot_, service, gas, accumulation_inputs, %{n0_: n0_})
  end

  def pre_single_accumulation(
        work_reports,
        deferred_transfers,
        always_accumulating_services,
        service
      ) do
    initial_g = Map.get(always_accumulating_services, service, 0)

    service_results =
      for %WorkReport{digests: wd, output: wt, specification: ws, authorizer_hash: wa} <-
            work_reports,
          %WorkDigest{service: ^service, gas_ratio: rg, result: rl, payload_hash: ry} <- wd,
          do: {rg, rl, ry, wt, ws, wa}

    total_gas =
      initial_g + Collections.sum_by(service_results, &elem(&1, 0))

    operands_services =
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

    # iT = [t ∣ t<−t, t_d = s]
    transfers = for t <- deferred_transfers, t.receiver == service, do: t

    {total_gas, operands_services ++ transfers}
  end

  # Formula (12.30) v0.7.2
  # Formula (12.31) v0.7.2
  @spec apply_last_accumulation(
          services_intermediate :: %{non_neg_integer() => ServiceAccount.t()},
          timeslot_ :: Types.timeslot(),
          accumulates_service_keys :: MapSet.t(non_neg_integer())
        ) :: %{Types.service_index() => ServiceAccount.t()}
  def apply_last_accumulation(services_intermediate, timeslot_, accumulates_service_keys) do
    # Formula (12.30) v0.7.2 - δ‡ ≡ { (s ↦ a′) ∣ (s ↦ a) ∈ δ† }
    for s <- accumulates_service_keys, reduce: services_intermediate do
      acc ->
        # Formula (12.31) v0.7.2 - a except a′_a = τ′ if s ∈ K(S)
        Map.get_and_update(acc, s, fn service ->
          if(service == nil,
            do: {nil, nil},
            else: {service, %{service | last_accumulation_slot: timeslot_}}
          )
        end)
        |> elem(1)
    end
  end

  # Formula (12.34) v0.7.2
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
