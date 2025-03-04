defmodule System.State.Services do
  alias System.State.ServiceAccount
  alias Block.Extrinsic.Preimage

  @doc """
  Formula (12.33) v0.6.0
  """
  def transition(services_intermediate_2, preimages, timeslot_) do
    # Formula (12.32) v0.6.0
    not_provided_preimages =
      Enum.filter(preimages, fn p -> Preimage.not_provided?(p, services_intermediate_2) end)

    Enum.reduce(not_provided_preimages, services_intermediate_2, fn preimage, acc_services ->
      updated_service_account =
        Map.get(acc_services, preimage.service, %ServiceAccount{})
        |> ServiceAccount.store_preimage(preimage.blob, timeslot_)

      Map.put(acc_services, preimage.service, updated_service_account)
    end)
  end

  def from_json(json_data) do
    for service <- json_data, into: %{} do
      {service[:id], ServiceAccount.from_json(service[:data])}
    end
  end
end
