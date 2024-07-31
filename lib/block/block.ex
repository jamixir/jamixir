defmodule Block do
  @type t :: %__MODULE__{
          header: Block.Header.t(),
          extrinsic: Block.Extrinsic.t()
        }

  # Equation (13)
  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: nil
  ]
end
