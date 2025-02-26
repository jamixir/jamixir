defmodule Block.Extrinsic.Guarantee.WorkExecutionError do
  alias Util.Collections
  # Formula (11.7) v0.6.2
  # J ∈         {∞,           ☇,          ⊚,        BAD,   BIG}
  @type t :: :out_of_gas | :panic | :bad_exports | :bad | :big

  # Formula (C.28) v0.6.2
  @codes %{out_of_gas: 1, panic: 2, bad_exports: 3, bad: 4, big: 5}

  def code(error) do
    @codes[error]
  end

  def code_name(code) do
    Collections.key_for_value(@codes, code)
  end
end
