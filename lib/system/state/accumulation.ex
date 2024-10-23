defmodule System.State.Accumulation do
  @moduledoc """
  Handles the accumulation and commitment process for services, validators, and the authorization queue.
  """

  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias System.{AccumulationResult, DeferredTransfer}
  alias System.State.{PrivilegedServices, ServiceAccount, Validator}
  alias Types
  alias Util.Collections

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

  @type accumulation_output :: {non_neg_integer(), Types.hash()}

  # Formula (174) v0.4.1
  @type o_tuple :: %{o: binary(), l: Types.hash(), a: binary(), k: Types.hash()}

  @doc """
  Accumulates the availability, core reports, and services, and returns the updated state.
  """
  @spec accumulate(list(), list(), list(), list(), list(), list()) ::
          {list(), list(), list(), list(), System.State.BeefyCommitmentMap.t()}
  def accumulate(
        _availability,
        _core_reports,
        _services_intermediate,
        _privileged_services,
        _next_validators,
        _authorization_queue
      ) do
    # TODO: Implement the logic for the accumulation process
    # Return a placeholder tuple for now
    {[], [], [], [], System.State.BeefyCommitmentMap.stub()}
  end

  # Formula (172) v0.4.1
  @spec outer_accumulation(
          non_neg_integer(),
          list(WorkReport.t()),
          t(),
          %{non_neg_integer() => non_neg_integer()}
        ) ::
          {:ok,
           {non_neg_integer(), t(), list(DeferredTransfer.t()), MapSet.t(accumulation_output)}}
          | {:error, atom()}
  def outer_accumulation(gas_limit, work_reports, acc_state, always_acc_services) do
    i = calculate_i(work_reports, gas_limit)

    if i == 0 do
      {:ok, {0, acc_state, [], {}}}
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
        work_reports
        |> Enum.take(i)
        |> Enum.flat_map(& &1.results)
        |> Enum.map(& &1.gas_ratio)
        |> Enum.sum()

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
          {:ok,
           {non_neg_integer(), t(), list(DeferredTransfer.t()), MapSet.t(accumulation_output)}}
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
    MapSet.new(
      Enum.flat_map(work_reports, & &1.results)
      |> Enum.map(& &1.service)
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
      [{m, :privileged_services}, {a, :next_validators}, {v, :authorizer_queue}]
      |> Enum.map(fn {service, key} ->
        %AccumulationResult{state: state} =
          single_accumulation(acc_state, work_reports, always_acc_services, service)

        Map.get(state, key)
      end)
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

  # This sepertion is to allow testing of single_accumulation without having to test the stub as well
  def pre_single_accumulation(work_reports, service_dict, service) do
    initial_g = Map.get(service_dict, service, 0)

    Enum.reduce(work_reports, {initial_g, []}, fn %WorkReport{
                                                    results: wr,
                                                    output: wo,
                                                    specification: %AvailabilitySpecification{
                                                      work_package_hash: sh
                                                    }
                                                  },
                                                  {acc_g, acc_p} ->
      wr
      |> Enum.filter(&(&1.service == service))
      |> Enum.reduce({acc_g, acc_p}, fn %WorkResult{gas_ratio: gr, result: ro, payload_hash: rl},
                                        {g, p} ->
        new_p = %{o: ro, l: rl, a: wo, k: sh}
        {g + gr, [new_p | p]}
      end)
    end)
  end

  # Stub for ΨA function
  @spec stub_psi_a(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          list(o_tuple())
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
end
