defmodule Block.Extrinsic.Guarantee.WorkExecutionError do
  alias Util.Collections
  # Formula (123) v0.4.5
  @type t :: :out_of_gas | :panic | :bad | :big

  # Formula (C.28) v0.5.0
  @codes %{out_of_gas: 1, panic: 2, bad: 3, big: 4}

  def code(error) do
    @codes[error]
  end

  def code_name(code) do
    Collections.key_for_value(@codes, code)
  end
end
