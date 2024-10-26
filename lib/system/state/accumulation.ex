defmodule System.State.Accumulation do
  @moduledoc """
  Handles the accumulation and commitment process for services, validators, and the authorization queue.
  """

  alias System.State.BeefyCommitmentMap
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias Block.Header
  alias System.{AccumulationResult, DeferredTransfer}
  alias System.State
  alias System.State.{PrivilegedServices, Ready, ServiceAccount, Validator, WorkPackageRootMap}
  alias Types
  alias Util.Collections
  alias System.PVM.AccumulationOperand

  use MapUnion

  @callback do_single_accumulation(
              t(),
              list(),
              map(),
              non_neg_integer()
            ) :: AccumulationResult.t()

  # Formula (169) v0.4.1
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
  Handles the accumulation process as described in Formula (177) and (178).
  """

  def accumulate(
        work_reports,
        %Header{timeslot: ht},
        %State{
          accumulation_history: accumulation_history,
          ready_to_accumulate: ready_to_accumulate,
          privileged_services: privileged_services,
          next_validators: next_validators,
          authorizer_queue: authorizer_queue,
          timeslot: state_timeslot
        },
        services_intermediate
      ) do
    # The total gas allocated across all cores for Accumulation. May be no smaller than GA ⋅ C + ∑g∈V(χg )(g).
    gas_limit =
      Constants.gas_accumulation() * Constants.core_count() +
        Enum.sum(Map.values(privileged_services.services_gas))

    accumulatable_reports =
      Block.Extrinsic.Guarantee.WorkReport.accumulatable_work_reports(
        work_reports,
        ht,
        accumulation_history,
        ready_to_accumulate
      )

    initial_state = %__MODULE__{
      privileged_services: privileged_services,
      services: services_intermediate,
      next_validators: next_validators,
      authorizer_queue: authorizer_queue
    }

    # Formula (176) v0.4.1
    # Formula (177) v0.4.1
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
          services: services_intermediate_2,
          next_validators: next_validators_,
          authorizer_queue: authorizer_queue_
        }, deferred_transfers, beefy_commitment_map}} ->
        # Formula (179) v0.4.1
        services_ = calculate_posterior_services(services_intermediate_2, deferred_transfers)
        # Formula (180) v0.4.1
        new_root_map = WorkPackageRootMap.create(Enum.take(accumulatable_reports, n))
        # Formula (181) v0.4.1
        accumulation_history_ = Enum.drop(accumulation_history, 1) ++ [new_root_map]
        {_, w_q} = WorkReport.separate_work_reports(work_reports, accumulation_history)
        # Formula (182) v0.4.1
        ready_to_accumulate_ =
          build_ready_to_accumulate_(
            ready_to_accumulate,
            accumulatable_reports,
            w_q,
            n,
            ht,
            state_timeslot
          )

        {:ok,
         %{
           services: services_,
           next_validators: next_validators_,
           authorizer_queue: authorizer_queue_,
           ready_to_accumulate: ready_to_accumulate_,
           privileged_services: privileged_services_,
           accumulation_history: accumulation_history_,
           beefy_commitment_map: beefy_commitment_map
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Formula (172) v0.4.1
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

  # Formula (173) v0.4.1
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
    ) ++
      MapSet.new(Map.keys(always_acc_services))
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

  # Formula (175) v0.4.1
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
            new_p = %AccumulationOperand{o: ro, l: rl, a: wo, k: ws.work_package_hash}
            {g + gr, [new_p | p]}
        end)
    end)
  end

  # Formula (179) v0.4.1
  def calculate_posterior_services(services_intermediate_2, transfers) do
    Enum.reduce(Map.keys(services_intermediate_2), services_intermediate_2, fn s, services ->
      selected_transfers = DeferredTransfer.select_transfers_for_destination(transfers, s)
      apply_transfers(services, s, selected_transfers)
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

  # stub for On-Transfer Invocation ΨT
  defp apply_transfers(services, service, transfers) do
    Enum.reduce(transfers, services, fn transfer, acc ->
      acc
      |> Map.update!(transfer.sender, fn account ->
        %{account | balance: account.balance - transfer.amount}
      end)
      |> Map.update!(service, fn account ->
        %{account | balance: account.balance + transfer.amount}
      end)
    end)
  end


  # Formula (182) v0.4.1
  @spec build_ready_to_accumulate_(
          ready_to_accumulate :: list(list(Ready.t())),
          w_star :: list(WorkReport.t()),
          w_q :: list({WorkReport.t(), MapSet.t(Types.hash())}),
          n :: non_neg_integer(),
          header_timeslot :: non_neg_integer(),
          state_timeslot :: non_neg_integer()
        ) :: list(list(Ready.t()))

  def build_ready_to_accumulate_(
        [],
        _w_star,
        _w_q,
        _n,
        _header_timeslot,
        _state_timeslot
      ) do
    []
  end

  def build_ready_to_accumulate_(
        ready_to_accumulate,
        w_star,
        w_q,
        n,
        header_timeslot,
        state_timeslot
      ) do
    e = length(ready_to_accumulate)
    m = Util.Time.epoch_phase(header_timeslot)
    tau_diff = header_timeslot - state_timeslot

    work_package_root_map = WorkPackageRootMap.create(Enum.take(w_star, n))

    Enum.map(0..(e - 1), fn i ->
      index = rem(m - i, e)

      cond do
        i == 0 ->
          WorkReport.edit_queue(w_q, work_package_root_map)

        i < tau_diff ->
          []

        true ->
          WorkReport.edit_queue(
            Enum.at(ready_to_accumulate, index) |> Enum.map(&Ready.to_tuple/1),
            work_package_root_map
          )
      end
    end)
  end
end
