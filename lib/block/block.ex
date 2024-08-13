defmodule Block do
  alias Codec.VariableSize

  @type t :: %__MODULE__{
          header: Block.Header.t(),
          extrinsic: Block.Extrinsic.t()
        }

  # Formula (13) v0.3.4
  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: nil
  ]

  defimpl Encodable do
    def encode(%Block{extrinsic: e, header: h}) do
      # Formula (280) v0.3.4
      Codec.Encoder.encode({
        h,
        VariableSize.new(e.tickets),
        e.disputes,
        VariableSize.new(e.preimages),
        VariableSize.new(e.availability),
        VariableSize.new(e.guarantees)
      })
    end
  end
end
