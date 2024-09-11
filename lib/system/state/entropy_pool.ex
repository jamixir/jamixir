defmodule System.State.EntropyPool do
  @moduledoc """
  Represents the state of the entropy pool in the system.
  section 6.4 - Sealing and Entropy Accumulation
  """

  alias Util.{Hash, Time, Crypto}
  alias System.State.EntropyPool

  @type t :: %__MODULE__{
          n0: Types.hash(),
          n1: Types.hash(),
          n2: Types.hash(),
          n3: Types.hash()
        }

  # Formula (66) v0.3.4
  defstruct n0: <<>>, n1: <<>>, n2: <<>>, n3: <<>>

  def posterior_entropy_pool(header, timeslot, %EntropyPool{n0: n0, n1: n1, n2: n2, n3: n3}) do
    # Formula (67) v0.3.4
    n0_ = Hash.blake2b_256(n0 <> Crypto.entropy_vrf(header.vrf_signature))

    # Formula (68) v0.3.4
    {n1_, n2_, n3_} =
      case Time.new_epoch?(timeslot, header.timeslot) do
        {:ok, true} ->
          {n0, n1, n2}

        {:ok, false} ->
          {n1, n2, n3}

        {:error, reason} ->
          raise "Error determining new epoch: #{reason}"
      end

    %EntropyPool{n0: n0_, n1: n1_, n2: n2_, n3: n3_}
  end

  defimpl Encodable do
    def encode(%EntropyPool{} = e) do
      Codec.Encoder.encode({e.n0, e.n1, e.n2, e.n3})
    end
  end
end
