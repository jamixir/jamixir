defmodule System.State.Accumulation do
  @moduledoc """
  Handles the accumulation and commitment process for services, validators, and the authorization queue.
  """

  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.AccumulationState
  alias System.DeferredTransfer
  alias System.State.PrivilegedServices
  alias Types
  alias Util.Collections

  use MapUnion

  @type accumulation_output :: {non_neg_integer(), Types.hash()}

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
          AccumulationState.t(),
          %{non_neg_integer() => non_neg_integer()}
        ) ::
          {non_neg_integer(), AccumulationState.t(), list(DeferredTransfer.t()),
           MapSet.t(accumulation_output)}
  def outer_accumulation(gas_limit, work_reports, acc_state, free_accumulation_services) do
    i = calculate_i(work_reports, gas_limit)

    if i == 0 do
      {0, acc_state, [], MapSet.new()}
    else
      # delta_star (Δ*)
      {g_star, o_star, t_star, b_star} =
        delta_star(acc_state, Enum.take(work_reports, i), free_accumulation_services)

      # Recursive call to outer_accumulation (Δ+)
      {j, o_prime, t, b} =
        outer_accumulation(
          gas_limit - g_star,
          Enum.drop(work_reports, i),
          o_star,
          MapSet.new()
        )

      {i + j, o_prime, t_star ++ t, b_star ++ b}
    end
  end

  @spec calculate_i(list(WorkReport.t()), non_neg_integer()) :: non_neg_integer()
  defp calculate_i(work_reports, gas_limit) do
    Enum.reduce_while(0..length(work_reports), 0, fn i, _acc ->
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
  @spec delta_star(AccumulationState.t(), list(WorkReport.t()), %{
          non_neg_integer() => non_neg_integer()
        }) ::
          {non_neg_integer(), AccumulationState.t(), list(DeferredTransfer.t()),
           MapSet.t(accumulation_output)}
  def delta_star(acc_state, work_reports, free_accumulation_services) do
    s =
      MapSet.new(
        Enum.flat_map(work_reports, & &1.results)
        |> Enum.map(& &1.service)
      ) ++
        MapSet.new(Map.keys(free_accumulation_services))

    {u, b, t} =
      Enum.reduce(s, {0, MapSet.new(), []}, fn service, {acc_u, acc_b, acc_t} ->
        {u, _, t, b} = delta_1(acc_state, work_reports, service)

        {
          acc_u + u,
          if(b, do: MapSet.put(acc_b, {service, b}), else: acc_b),
          t ++ acc_t
        }
      end)

    %AccumulationState{privileged_services: %PrivilegedServices{
      manager_service: m,
      alter_authorizer_service: a,
      alter_validator_service: v
    }} = acc_state

    {x_prime, i_prime, q_prime} =
      [
        {:privileged_services, m},
        {:next_validators, a},
        {:authorizer_queue, v}
      ]
      |> Enum.map(fn {key, service} ->
        delta_1(acc_state, work_reports, service)
        |> elem(1)
        |> Map.get(key)
      end)
      |> List.to_tuple()

    d_prime =
      Map.drop(acc_state.services, s) ++
        Collections.union(Enum.map(s, &elem(delta_1(acc_state, work_reports, &1), 1).services))

    updated_state = %AccumulationState{
      services: d_prime,
      next_validators: i_prime,
      authorizer_queue: q_prime,
      privileged_services: x_prime
    }

    {u, updated_state, List.flatten(t), b}
  end

  # Placeholder for delta_1 function
  @spec delta_1(AccumulationState.t(), list(WorkReport.t()), non_neg_integer()) ::
          {non_neg_integer(), AccumulationState.t(), list(DeferredTransfer.t()),
           Types.hash() | nil}
  defp delta_1(_state, _work_reports, _service) do
    # TODO: Implement delta_1 logic
    {0, %AccumulationState{}, [], nil}
  end
end
