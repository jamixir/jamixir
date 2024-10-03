defmodule System.State.Services do
  @moduledoc """
  Handles service-related state transitions, including processing preimages and gas accounting.
  """

  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.State.ServiceAccount

  @doc """
  Formula (158) v0.3.4
  """
  def process_preimages(services, preimages, timeslot_) do
    Enum.reduce(preimages, services, fn preimage, acc_services ->
      updated_service_account =
        Map.get(acc_services, preimage.service_index, %ServiceAccount{})
        |> ServiceAccount.store_preimage(preimage.data, timeslot_)

      Map.put(acc_services, preimage.service_index, updated_service_account)
    end)
  end

  # Formula (159) v0.3.4
  def service_index_set(assurances, core_reports_intermediate_1, privileged_services) do
    work_report_indices =
      Assurance.available_work_reports(assurances, core_reports_intermediate_1)
      |> Enum.flat_map(fn %WorkReport{work_results: r} ->
        Enum.map(r, & &1.service_index)
      end)

    privileged_indices = [
      privileged_services.manager_service,
      privileged_services.alter_authorizer_service,
      privileged_services.alter_validator_service
    ]

    work_report_indices
    |> Enum.concat(privileged_indices)
    |> MapSet.new()
  end

  # Formula (160) v0.3.4
  def gas_attributable_for_service(
        service_index,
        assurances,
        core_reports_intermediate_1,
        services_intermediate
      ) do
    # w∈W
    Assurance.available_work_reports(assurances, core_reports_intermediate_1)
    |> Enum.map(fn %WorkReport{work_results: wr} ->
      gas_for_work_report(wr, services_intermediate, service_index)
    end)
    |> Enum.sum()
  end

  defp gas_for_work_report(r, services_intermediate, s) do
    # r∈wr ,rs =s
    service_gas_limit =
      Enum.filter(r, fn %{service_index: s_index} -> s_index == s end)
      |> Enum.map(fn %{service_index: s} -> services_intermediate[s].gas_limit_g end)
      |> Enum.sum()

    # r∈wr
    total_gas_limit =
      r
      |> Enum.map(fn %{service_index: s} -> services_intermediate[s].gas_limit_g end)
      |> Enum.sum()

    # ∑ [rg]
    total_prioritization =
      r
      |> Enum.map(fn %{gas_prioritization_ratio: rg} -> rg end)
      |> Enum.sum()

    ga = Constants.gas_accumulation()

    gas_share =
      r
      |> Enum.map(fn %{gas_prioritization_ratio: rg} ->
        div(rg * (ga - total_gas_limit), total_prioritization)
      end)
      |> Enum.sum()

    service_gas_limit + gas_share
  end
end
