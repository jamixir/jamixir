defmodule System.State.Accumulation do
  @moduledoc """
  Chapter 12 - accumulation
  """

  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias PVM.Accumulate
  alias System.{AccumulationResult, DeferredTransfer, State}

  alias System.State.{
    BeefyCommitmentMap,
    PrivilegedServices,
    Ready,
    ServiceAccount,
    Validator
  }

  alias Types
  use MapUnion
  use AccessStruct
  import Utils

  # (Accumulation.t(), service_index) -> PVM.Host.Accumulate.Context.t()
  @type ctx_init_fn :: (t(), non_neg_integer() -> PVM.Host.Accumulate.Context.t())
  @type ctx :: %{timeslot: non_neg_integer(), ctx_init_fn: ctx_init_fn()}
  @callback do_single_accumulation(
              t(),
              list(),
              map(),
              non_neg_integer(),
              ctx()
            ) ::
              AccumulationResult.t()
  @callback do_transition(list(), State.t(), ctx()) :: any()

  # Formula (12.13) v0.6.4 - U
  @type t :: %__MODULE__{
          # d: Service accounts state (δ)
          services: %{non_neg_integer() => ServiceAccount.t()},
          # i: Upcoming validator keys (ι)
          next_validators: list(Validator.t()),
          # q: Queue of work-reports (φ)
          authorizer_queue: list(list(Types.hash())),
          # x: Privileges state (χ)
          privileged_services: PrivilegedServices.t()
        }

  defstruct services: %{},
            next_validators: [],
            authorizer_queue: [[]],
            privileged_services: %PrivilegedServices{}

  @doc """
  Handles the accumulation process as described in Formula (12.21) and (12.22) v0.6.4
  """
  def transition(w, t_, n0_, s) do
    ctx_init_fn = PVM.Accumulate.Utils.initializer(n0_, t_)
    module = Application.get_env(:jamixir, :accumulation, __MODULE__)
    ctx = %{timeslot: t_, ctx_init_fn: ctx_init_fn}
    module.do_transition(w, s, ctx)
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
        %{timeslot: timeslot_} = ctx
      ) do
    # Formula (12.20) v0.6.4
    gas_limit =
      max(
        Constants.gas_total_accumulation(),
        Constants.gas_accumulation() * Constants.core_count() +
          Enum.sum(Map.values(privileged_services.services_gas))
      )

    # W∗
    accumulatable_reports =
      WorkReport.accumulatable_work_reports(
        work_reports,
        timeslot_,
        accumulation_history,
        ready_to_accumulate
      )

    initial_state = %__MODULE__{
      privileged_services: privileged_services,
      services: services,
      next_validators: next_validators,
      authorizer_queue: authorizer_queue
    }

    # Formula (12.21) v0.6.4
    {n, o, deferred_transfers, beefy_commitment, _u} =
      sequential_accumulation(
        gas_limit,
        accumulatable_reports,
        initial_state,
        privileged_services.services_gas,
        ctx
      )

    # Formula (12.22) v0.6.4
    %__MODULE__{
      privileged_services: privileged_services_,
      services: services_intermediate,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_
    } = o

    # Formula (12.28) v0.6.4
    services_intermediate_2 =
      apply_transfers(services_intermediate, deferred_transfers, timeslot_)

    w_star_n = Enum.take(accumulatable_reports, n)
    # Formula (12.31) v0.6.4
    work_package_hashes = WorkReport.work_package_hashes(w_star_n)
    # Formula (12.32) v0.6.4
    accumulation_history_ = Enum.drop(accumulation_history, 1) ++ [work_package_hashes]
    {_, w_q} = WorkReport.separate_work_reports(work_reports, accumulation_history)
    # Formula (12.33) v0.6.4
    ready_to_accumulate_ =
      build_ready_to_accumulate_(
        ready_to_accumulate,
        work_package_hashes,
        w_q,
        timeslot_,
        timeslot
      )

    %{
      services: services_intermediate_2,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_,
      ready_to_accumulate: ready_to_accumulate_,
      privileged_services: privileged_services_,
      accumulation_history: accumulation_history_,
      beefy_commitment: beefy_commitment,
      # Formula (12.24) v0.6.4
      accumulation_stats: accumulate_statistics(w_star_n),
      # Formula (12.30) v0.6.4
      deferred_transfers_stats: deferred_transfers_stats(deferred_transfers)
    }
  end

  # Formula (12.23) v0.6.4
  # Formula (12.24) v0.6.4
  # Formula (12.25) v0.6.4
  def accumulate_statistics(work_reports) do
    for w <- work_reports, r <- w.results, reduce: %{} do
      stat ->
        case Map.get(stat, r.service) do
          nil -> Map.put(stat, r.service, {r.gas_used, 1})
          {total_gas, count} -> Map.put(stat, r.service, {total_gas + r.gas_used, count + 1})
        end
    end
  end

  # Formula (12.29) v0.6.4
  # Formula (12.30) v0.6.4
  def deferred_transfers_stats(deferred_transfers) do
    for t <- deferred_transfers, reduce: %{} do
      stat ->
        case Map.get(stat, t.receiver) do
          nil ->
            Map.put(stat, t.receiver, {1, t.amount})

          {count, total_amount} ->
            Map.put(stat, t.receiver, {count + 1, total_amount + t.amount})
        end
    end
  end

  # Formula (12.16) v0.6.4
  @spec sequential_accumulation(
          non_neg_integer(),
          list(WorkReport.t()),
          t(),
          %{non_neg_integer() => non_neg_integer()},
          ctx()
        ) ::
          {t(), list(DeferredTransfer.t()), BeefyCommitmentMap.t(),
           list({Types.service_index(), Types.gas()})}

  def sequential_accumulation(
        gas_limit,
        work_reports,
        acc_state,
        always_acc_services,
        ctx
      ) do
    i = number_of_work_reports_to_accumumulate(work_reports, gas_limit)

    if i == 0 do
      {0, acc_state, [], MapSet.new(), []}
    else
      {o_star, t_star, b_star, u_star} =
        parallelized_accumulation(
          acc_state,
          Enum.take(work_reports, i),
          always_acc_services,
          ctx
        )

      g_star = Enum.sum(for {_, g} <- u_star, do: g)

      {j, o_prime, t, b, u} =
        sequential_accumulation(
          gas_limit - g_star,
          Enum.drop(work_reports, i),
          o_star,
          Map.new(),
          ctx
        )

      {i + j, o_prime, t_star ++ t, b_star ++ b, u_star ++ u}
    end
  end

  @spec number_of_work_reports_to_accumumulate(list(WorkReport.t()), non_neg_integer()) ::
          non_neg_integer()
  def number_of_work_reports_to_accumumulate(work_reports, gas_limit) do
    Enum.reduce_while(1..length(work_reports), 0, fn i, _acc ->
      sum =
        Enum.sum(
          for r <- Enum.flat_map(Enum.take(work_reports, i), & &1.results), do: r.gas_ratio
        )

      if sum <= gas_limit do
        {:cont, i}
      else
        {:halt, i - 1}
      end
    end)
  end

  # Formula (12.17) v0.6.4
  @spec parallelized_accumulation(
          t(),
          list(WorkReport.t()),
          %{non_neg_integer() => non_neg_integer()},
          ctx()
        ) ::
          {t(), list(DeferredTransfer.t()), BeefyCommitmentMap.t(),
           list({Types.service_index(), Types.gas()})}
  def parallelized_accumulation(
        acc_state,
        work_reports,
        always_acc_services,
        ctx
      ) do
    services = collect_services(work_reports, always_acc_services)

    # {x', i', q'}
    {privileged_services_, next_validators_, authorizer_queue_} =
      accumulate_privileged_services(
        acc_state,
        work_reports,
        always_acc_services,
        ctx
      )

    d = acc_state.services

    {service_hash_pairs, transfers, n, m, service_gas} =
      Enum.reduce(services, {MapSet.new(), [], %{}, MapSet.new(), []}, fn service,
                                                                          {acc_output,
                                                                           acc_transfers, acc_n,
                                                                           acc_m,
                                                                           acc_service_gas} ->
        # ar stands for accumulation result
        ar =
          single_accumulation(
            acc_state,
            work_reports,
            services,
            service,
            ctx
          )

        keys_to_drop = Map.keys(Map.delete(d, service))
        service_n = Map.drop(ar.state.services, keys_to_drop)

        service_m =
          MapSet.difference(keys_set(d), keys_set(ar.state.services))

        {
          if(is_binary(ar.output),
            do: MapSet.put(acc_output, {service, ar.output}),
            else: acc_output
          ),
          acc_transfers ++ ar.transfers,
          acc_n ++ service_n,
          acc_m ++ service_m,
          acc_service_gas ++ [{service, ar.gas_used}]
        }
      end)

    accumulation_state = %__MODULE__{
      services: Map.drop(d ++ n, MapSet.to_list(m)),
      privileged_services: privileged_services_,
      next_validators: next_validators_,
      authorizer_queue: authorizer_queue_
    }

    {accumulation_state, List.flatten(transfers), service_hash_pairs, service_gas}
  end

  def collect_services(work_reports, always_acc_services) do
    for(
      r <- Enum.flat_map(work_reports, & &1.results),
      do: r.service,
      into: MapSet.new()
    ) ++ keys_set(always_acc_services)
  end

  def accumulate_privileged_services(
        acc_state,
        work_reports,
        always_acc_services,
        ctx
      ) do
    %__MODULE__{
      privileged_services: ps
    } = acc_state

    for {service, key} <- [
          {ps.privileged_services_service, :privileged_services},
          {ps.next_validators_service, :next_validators},
          {ps.authorizer_queue_service, :authorizer_queue}
        ] do
      %{state: state} =
        single_accumulation(
          acc_state,
          work_reports,
          always_acc_services,
          service,
          ctx
        )

      Map.get(state, key)
    end
    |> List.to_tuple()
  end

  # Formula (12.19) v0.6.4
  def single_accumulation(acc_state, work_reports, service_dict, service, ctx) do
    module = Application.get_env(:jamixir, :accumulation_module, __MODULE__)

    module.do_single_accumulation(
      acc_state,
      work_reports,
      service_dict,
      service,
      ctx
    )
  end

  def do_single_accumulation(
        acc_state,
        work_reports,
        service_dict,
        service,
        %{timeslot: timeslot_, ctx_init_fn: ctx_init_fn}
      ) do
    {gas, operands} = pre_single_accumulation(work_reports, service_dict, service)

    PVM.accumulate(acc_state, timeslot_, service, gas, operands, ctx_init_fn)
    |> AccumulationResult.new()
  end

  def pre_single_accumulation(work_reports, service_dict, service) do
    initial_g = Map.get(service_dict, service, 0)

    service_results =
      for %WorkReport{results: wr, output: wo, specification: ws, authorizer_hash: wa} <-
            work_reports,
          %WorkResult{service: ^service, gas_ratio: gr, result: rd, payload_hash: ry} <- wr,
          do: {gr, rd, ry, wo, ws, wa}

    total_gas =
      initial_g +
        Enum.sum(Stream.map(service_results, &elem(&1, 0)))

    operands =
      for {_, rd, ry, wo, ws, wa} <- service_results do
        %Accumulate.Operand{
          h: ws.work_package_hash,
          e: ws.exports_root,
          a: wa,
          o: wo,
          y: ry,
          d: rd
        }
      end

    {total_gas, operands}
  end

  # Formula (12.27) v0.6.4
  # Formula (12.28) v0.6.4
  def apply_transfers(services_intermediate, transfers, timeslot) do
    Enum.reduce(Map.keys(services_intermediate), %{}, fn s, acc ->
      selected_transfers = DeferredTransfer.select_transfers_for_destination(transfers, s)

      service_with_transfers_applied =
        PVM.on_transfer(services_intermediate, timeslot, s, selected_transfers)

      Map.put(acc, s, service_with_transfers_applied)
    end)
  end

  # Formula (12.33) v0.6.4
  @spec build_ready_to_accumulate_(
          ready_to_accumulate :: list(list(Ready.t())),
          w_star :: list(WorkReport.t()),
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
