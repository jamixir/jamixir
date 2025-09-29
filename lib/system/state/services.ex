defmodule System.State.Services do
  alias System.State.Accumulation
  alias System.State.ServiceAccount

  # Formula (12.38) v0.7.2
  def transition(services_intermediate_2, preimages, timeslot_) do
    Accumulation.integrate_preimages(services_intermediate_2, preimages, timeslot_)
  end

  def from_json(json_data) do
    for service <- json_data, into: %{} do
      {service[:id], ServiceAccount.from_json(service[:data])}
    end
  end
end
