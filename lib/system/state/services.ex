defmodule System.State.Services do
  @moduledoc """
  Handles service-related state transitions, including processing preimages and gas accounting.
  """

  alias System.State.ServiceAccount

  @doc """
  Formula (161) v0.4.5
  """
  def process_preimages(services, preimages, timeslot_) do
    Enum.reduce(preimages, services, fn preimage, acc_services ->
      updated_service_account =
        Map.get(acc_services, preimage.service, %ServiceAccount{})
        |> ServiceAccount.store_preimage(preimage.blob, timeslot_)

      Map.put(acc_services, preimage.service, updated_service_account)
    end)
  end
end
