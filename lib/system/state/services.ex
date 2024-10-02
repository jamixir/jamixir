defmodule System.State.Services do
  @moduledoc """
  Handles service-related state transitions, including processing preimages.
  """

  alias System.State.ServiceAccount

  @doc """
  Formula (158) v0.3.4
  """
  def process_preimages(services, preimages, timeslot) do
    Enum.reduce(preimages, services, fn preimage, acc_services ->
      updated_service_account =
        Map.get(acc_services, preimage.service_index, %ServiceAccount{})
        |> ServiceAccount.store_preimage(preimage.data, timeslot)

      Map.put(acc_services, preimage.service_index, updated_service_account)
    end)
  end
end
