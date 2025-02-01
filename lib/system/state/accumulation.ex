defmodule System.State.Accumulation do
  @moduledoc """
  Handles the accumulation and commitment process for services, validators, and the authorization queue.
  """

  alias System.State.BeefyCommitmentMap
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias PVM.Accumulate
  alias System.{AccumulationResult, DeferredTransfer, State}
  alias System.State.{PrivilegedServices, Ready, ServiceAccount, Validator}
  alias Types
  alias Util.Collections

  use MapUnion

  @behaviour Access

  @impl Access
  def fetch(container, key) do
    Map.fetch(Map.from_struct(container), key)
  end

  @impl Access
  def get_and_update(container, key, fun) do
    {get, update} = fun.(Map.get(container, key))
    {get, Map.put(container, key, update)}
  end

  @impl Access
  def pop(container, key) do
    value = Map.get(container, key)
    {value, Map.put(container, key, nil)}
  end

  @callback do_single_accumulation(t(), list(), map(), non_neg_integer()) ::
              AccumulationResult.t()
  @callback do_transition(list(), non_neg_integer(), State.t()) :: any()

  # Formula (12.3) v0.6.0 - U
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
  Handles the accumulation process as described in Formula (12.16) and (12.17) v0.5.4
  """

  def transition(w, t_, s) do
    module = Application.get_env(:jamixir, :accumulation, __MODULE__)
    module.do_transition(w, t_, s)
  end

  def do_transition(
        work_reports,
        timeslot_,
        %State{
          accumulation_history: accumulation_history,
          ready_to_accumulate: ready_to_accumulate,
          privileged_services: privileged_services,
          next_validators: next_validators,
          authorizer_queue: authorizer_queue,
          services: services,
          timeslot: timeslot
        }
      ) do
    # Formula (12.20) v0.5.4
    gas_limit =
      max(
        Constants.gas_total_accumulation(),
        Constants.gas_accumulation() * Constants.core_count() +
          Enum.sum(Map.values(privileged_services.services_gas))
      )

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

    # Formula (12.21) v0.5.4
    # Formula (12.22) v0.5.4
    case outer_accumulation(
           gas_limit,
           accumulatable_reports,
           initial_state,
           privileged_services.services_gas
         ) do
      {:ok,
       {n,
        %__MODULE__{
          privileged_services: privileged_services_,
          services: services_intermediate,
          next_validators: next_validators_,
          authorizer_queue: authorizer_queue_
        }, deferred_transfers, beefy_commitment}} ->
        # Formula (12.24) v0.6.0
        services_intermediate_2 =
          calculate_posterior_services(services_intermediate, deferred_transfers, timeslot_)

        # Formula (12.25) v0.6.0
        work_package_hashes = WorkReport.work_package_hashes(Enum.take(accumulatable_reports, n))
        # Formula (12.26) v0.6.0
        accumulation_history_ = Enum.drop(accumulation_history, 1) ++ [work_package_hashes]
        {_, w_q} = WorkReport.separate_work_reports(work_reports, accumulation_history)
        # Formula (12.27) v0.6.0
        ready_to_accumulate_ =
          build_ready_to_accumulate_(
            ready_to_accumulate,
            work_package_hashes,
            w_q,
            timeslot_,
            timeslot
          )

        {:ok,
         %{
           services: services_intermediate_2,
           next_validators: next_validators_,
           authorizer_queue: authorizer_queue_,
           ready_to_accumulate: ready_to_accumulate_,
           privileged_services: privileged_services_,
           accumulation_history: accumulation_history_,
           beefy_commitment: beefy_commitment
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Formula (12.16) v0.6.0
  @spec outer_accumulation(
          non_neg_integer(),
          list(WorkReport.t()),
          t(),
          %{non_neg_integer() => non_neg_integer()}
        ) ::
          {:ok, {non_neg_integer(), t(), list(DeferredTransfer.t()), BeefyCommitmentMap.t()}}
          | {:error, atom()}
  def outer_accumulation(gas_limit, work_reports, acc_state, always_acc_services) do
    i = calculate_i(work_reports, gas_limit)

    if i == 0 do
      {:ok, {0, acc_state, [], MapSet.new()}}
    else
      with {:ok, {g_star, o_star, t_star, b_star}} <-
             parallelized_accumulation(acc_state, Enum.take(work_reports, i), always_acc_services),
           {:ok, {j, o_prime, t, b}} <-
             outer_accumulation(
               gas_limit - g_star,
               Enum.drop(work_reports, i),
               o_star,
               Map.new()
             ) do
        {:ok, {i + j, o_prime, t_star ++ t, b_star ++ b}}
      else
        {:error, error} -> {:error, error}
      end
    end
  end

  @spec calculate_i(list(WorkReport.t()), non_neg_integer()) :: non_neg_integer()
  def calculate_i(work_reports, gas_limit) do
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

  # Formula (178) v0.4.5
  # TODO review to Formula 12.17 v0.6.0
  @spec parallelized_accumulation(t(), list(WorkReport.t()), %{
          non_neg_integer() => non_neg_integer()
        }) ::
          {:ok, {non_neg_integer(), t(), list(DeferredTransfer.t()), BeefyCommitmentMap.t()}}
          | {:error, atom()}
  def parallelized_accumulation(acc_state, work_reports, always_acc_services) do
    s = collect_services(work_reports, always_acc_services)

    with :ok <- validate_services(acc_state, s) do
      {u, b, t} = accumulate_services(acc_state, work_reports, always_acc_services, s)
      updated_state = update_accumulation_state(acc_state, work_reports, always_acc_services, s)
      {:ok, {u, updated_state, List.flatten(t), b}}
    end
  end

  def collect_services(work_reports, always_acc_services) do
    for(
      r <- Enum.flat_map(work_reports, & &1.results),
      do: r.service,
      into: MapSet.new()
    ) ++ Utils.keys_set(always_acc_services)
  end

  def accumulate_services(acc_state, work_reports, always_acc_services, s) do
    Enum.reduce(s, {0, MapSet.new(), []}, fn service, {acc_u, acc_b, acc_t} ->
      %AccumulationResult{gas_used: u, transfers: t, output: b} =
        single_accumulation(acc_state, work_reports, always_acc_services, service)

      {
        acc_u + u,
        if(is_binary(b), do: MapSet.put(acc_b, {service, b}), else: acc_b),
        t ++ acc_t
      }
    end)
  end

  @spec update_accumulation_state(
          t(),
          list(WorkReport.t()),
          %{non_neg_integer() => non_neg_integer()},
          MapSet.t(non_neg_integer())
        ) :: t()
  def update_accumulation_state(
        %__MODULE__{} = acc_state,
        work_reports,
        always_acc_services,
        s
      ) do
    %__MODULE__{
      privileged_services: %PrivilegedServices{
        manager_service: m,
        alter_authorizer_service: a,
        alter_validator_service: v
      }
    } = acc_state

    {x_prime, i_prime, q_prime} =
      for {s, key} <- [{m, :privileged_services}, {a, :next_validators}, {v, :authorizer_queue}] do
        %AccumulationResult{state: state} =
          single_accumulation(acc_state, work_reports, always_acc_services, s)

        Map.get(state, key)
      end
      |> List.to_tuple()

    d_prime =
      Map.drop(acc_state.services, MapSet.to_list(s)) ++
        Collections.union(
          Enum.map(
            s,
            &single_accumulation(acc_state, work_reports, always_acc_services, &1).state.services
          )
        )

    %__MODULE__{
      services: d_prime,
      next_validators: i_prime,
      authorizer_queue: q_prime,
      privileged_services: x_prime
    }
  end

  def validate_services(%__MODULE__{services: d}, services) do
    if Enum.all?(services, &Map.has_key?(d, &1)) do
      :ok
    else
      {:error, :invalid_service}
    end
  end

  # Formula (180) v0.4.5
  # TODO to Formula 12.19 v0.6.0
  def single_accumulation(acc_state, work_reports, service_dict, service) do
    module = Application.get_env(:jamixir, :accumulation_module, __MODULE__)

    module.do_single_accumulation(acc_state, work_reports, service_dict, service)
  end

  def do_single_accumulation(acc_state, work_reports, service_dict, service) do
    {g, p} = pre_single_accumulation(work_reports, service_dict, service)
    stub_psi_a(acc_state, service, g, p)
  end

  # This separation is to allow testing of single_accumulation without having to test the stub as well
  def pre_single_accumulation(work_reports, service_dict, service) do
    initial_g = Map.get(service_dict, service, 0)

    Enum.reduce(work_reports, {initial_g, []}, fn
      %WorkReport{results: wr, output: wo, specification: ws}, {acc_g, acc_p} ->
        wr
        |> Enum.filter(&(&1.service == service))
        |> Enum.reduce({acc_g, acc_p}, fn
          %WorkResult{gas_ratio: gr, result: ro, payload_hash: rl}, {g, p} ->
            new_p = %Accumulate.Operand{o: ro, l: rl, a: wo, k: ws.work_package_hash}
            {g + gr, [new_p | p]}
        end)
    end)
  end

  # Formula (12.24) v0.5.4
  def calculate_posterior_services(services_intermediate_2, transfers, timeslot) do
    Enum.reduce(Map.keys(services_intermediate_2), services_intermediate_2, fn s, services ->
      selected_transfers = DeferredTransfer.select_transfers_for_destination(transfers, s)
      %{services | s => PVM.on_transfer(services, timeslot, s, selected_transfers)}
    end)
  end

  # Stub for ΨA function
  @spec stub_psi_a(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          list(AccumulationOperand.t())
        ) :: AccumulationResult.t()
  defp stub_psi_a(acc_state, _service, gas_used, _payloads) do
    # Replace this with actual implementation later
    %AccumulationResult{
      state: acc_state,
      transfers: [],
      output: nil,
      gas_used: gas_used
    }
  end

  # Formula (12.27) v0.5.4
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
            WorkReport.edit_queue(w_q, work_package_hashes)

          i < timeslot_ - timeslot ->
            []

          true ->
            WorkReport.edit_queue(
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
