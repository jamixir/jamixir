defmodule Block.Extrinsic.Preimage do
  # Formula (155) v0.3.4
  @type t :: %__MODULE__{
          # i
          service_index: non_neg_integer(),
          # d
          data: binary()
        }

  # i
  defstruct service_index: 0,
            # d
            data: <<>>


  defimpl Encodable do
    def encode(%Block.Extrinsic.Preimage{service_index: i, data: d}) do
      Codec.Encoder.encode({
        i,
        d
      })
    end
  end
end
