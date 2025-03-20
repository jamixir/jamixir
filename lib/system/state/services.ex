defmodule System.State.Services do
  alias System.State.ServiceAccount
  alias Block.Extrinsic.Preimage

  @doc """
  Formula (12.39) v0.6.4
  """
  def transition(services_intermediate_2, preimages, timeslot_) do
    # Formula (12.38) v0.6.4
    not_provided_preimages =
      Enum.filter(preimages, &Preimage.not_provided?(&1, services_intermediate_2))

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
