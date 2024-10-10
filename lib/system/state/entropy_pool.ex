defmodule System.State.EntropyPool do
  @moduledoc """
  Represents the state of the entropy pool in the system.
  section 6.4 - Sealing and Entropy Accumulation
  """

  alias System.State.EntropyPool
  alias Util.{Hash, Time}

  @type t :: %__MODULE__{
          n0: Types.hash(),
          n1: Types.hash(),
          n2: Types.hash(),
          n3: Types.hash()
        }

  # Formula (66) v0.4.1
  defstruct n0: <<>>, n1: <<>>, n2: <<>>, n3: <<>>

  # Formula (68) v0.4.1
  @spec rotate_history(Block.Header.t(), non_neg_integer(), t()) ::
          t()
  def rotate_history(header, timeslot, %EntropyPool{n0: n0, n1: n1, n2: n2} = pool) do
    if Time.new_epoch?(timeslot, header.timeslot) do
      %EntropyPool{pool | n1: n0, n2: n1, n3: n2}
    else
      pool
    end
  end

  # Formula (67) v0.4.1
  def calculate_entropy_pool_(vrf_output, %EntropyPool{n0: n0} = pool) do
    %EntropyPool{pool | n0: Hash.blake2b_256(n0 <> vrf_output)}
  end

  defimpl Encodable do
    def encode(%EntropyPool{} = e) do
      Codec.Encoder.encode({e.n0, e.n1, e.n2, e.n3})
    end
  end

  def from_json(json) do
    [n0, n1, n2, n3] = Utils.hex_to_binary(json)
    %__MODULE__{n0: n0, n1: n1, n2: n2, n3: n3}
  end
end
