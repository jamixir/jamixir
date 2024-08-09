defmodule System.State.EntropyPool do
  @moduledoc """
  Represents the state of the entropy pool in the system.
  section 6.4 - Sealing and Entropy Accumulation
  """

  alias Util.{Hash, Time, Crypto}
  alias System.State.EntropyPool

  @type t :: %__MODULE__{
          current: binary(),
          history: list(binary())
        }

  defstruct current: "", history: []

  def posterior_entropy_pool(header, timeslot, %EntropyPool{
        current: current_entropy,
        history: history
      }) do
    new_entropy = Hash.blake2b_256(current_entropy <> Crypto.entropy_vrf(header.vrf_signature))

    history =
      case Time.new_epoch?(timeslot, header.timeslot) do
        {:ok, true} ->
          [new_entropy | Enum.take(history, 2)]

        {:ok, false} ->
          history

        {:error, reason} ->
          raise "Error determining new epoch: #{reason}"
      end

    %EntropyPool{
      current: new_entropy,
      history: history
    }
  end
end
