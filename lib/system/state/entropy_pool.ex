defmodule System.State.EntropyPool do
  @moduledoc """
  Represents the state of the entropy pool in the system.
  section 6.4 - Sealing and Entropy Accumulation
  """

  alias Util.{Hash, Time, Crypto}
  alias System.State.EntropyPool

  @type t :: %__MODULE__{
          current: Types.hash(),
          history: list(Types.hash())
        }

  # Formula (66) v0.3.4
  defstruct current: <<>>, history: [<<>>, <<>>, <<>>]

  def posterior_entropy_pool(header, timeslot, %EntropyPool{
        current: current_entropy,
        history: history
      }) do
    # Formula (67) v0.3.4
    new_entropy = Hash.blake2b_256(current_entropy <> Crypto.entropy_vrf(header.vrf_signature))

    # Formula (68) v0.3.4
    history =
      case Time.new_epoch?(timeslot, header.timeslot) do
        {:ok, true} ->
          [current_entropy | Enum.take(history, 2)]

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

  defimpl Encodable do
    def encode(%EntropyPool{} = e) do
      Codec.Encoder.encode([e.current] ++ e.history)
    end
  end
end
