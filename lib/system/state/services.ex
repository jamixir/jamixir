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
      |> Enum.flat_map(fn %WorkReport{work_results: results} ->
        Enum.map(results, & &1.service_index)
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
  def compute_gas_attributable_all(
        assurances,
        core_reports_intermediate_1,
        services_intermediate
      ) do
    Assurance.available_work_reports(assurances, core_reports_intermediate_1)
    |> Enum.map(fn %{work_results: wr, service_index: s} ->
      gas_for_work_report(wr, services_intermediate, s)
    end)
    |> Enum.sum()
  end

  defp gas_for_work_report(work_results, services_intermediate, s) do
    ga = Constants.gas_accumulation()

    total_gas_limit =
      work_results
      |> Enum.map(fn %{service_index: s} -> services_intermediate[s].gas_limit_g end)
      |> Enum.sum()

    gas_prioritization_ratios = work_results |> Enum.map(& &1.gas_prioritization_ratio)
    # ∑ [rg]
    total_prioritization = gas_prioritization_ratios |> Enum.sum()

    gas_share =
      gas_prioritization_ratios
      |> Enum.map(fn rg ->
        div(rg * (ga - total_gas_limit), total_prioritization)
      end)
      |> Enum.sum()

    # ∑ δ†[rₛ]₉
    service_gas_limit =
      Enum.filter(work_results, fn %{service_index: s_index} -> s_index == s end)
      |> Enum.map(fn %{service_index: s} -> services_intermediate[s].gas_limit_g end)
      |> Enum.sum()

    service_gas_limit + gas_share
  end
end
