defmodule Block.Extrinsic.Guarantee.WorkExecutionError do
  # Formula (124) v0.3.4
  @type t :: :infinite | :halt | :bad | :big

  # Formula (290) v0.3.4
  @codes %{infinite: 1, halt: 2, bad: 3, big: 4}

  def code(error) do
    @codes[error]
  end
end
