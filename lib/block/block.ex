defmodule Block do
  @type t :: %__MODULE__{
          header: Block.Header.t(),
          extrinsic: Block.Extrinsic.t()
        }

  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: nil
  ]
end
