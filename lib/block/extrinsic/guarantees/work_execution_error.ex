defmodule Block.Extrinsic.Guarantee.WorkExecutionError do
  alias Util.Collections
  # Formula (123) v0.4.1
  @type t :: :infinite | :halt | :bad | :big

  # Formula (311) v0.4.1
  @codes %{infinite: 1, halt: 2, bad: 3, big: 4}

  def code(error) do
    @codes[error]
  end

  def code_name(code) do
    Collections.key_for_value(@codes, code)
  end
end
