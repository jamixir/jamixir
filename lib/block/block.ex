defmodule Block do
  @type t :: %__MODULE__{
    header: Block.Header.t(),
    extrinsic: Block.Extrinsic.t()
  }

  defstruct [
    header: nil, #Hp
    extrinsic: nil, # Hr
  ]
end
