defmodule Block do
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
end
