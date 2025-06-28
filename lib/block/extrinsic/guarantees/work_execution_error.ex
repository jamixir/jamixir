defmodule Block.Extrinsic.Guarantee.WorkExecutionError do
  alias Util.Collections
  # Formula (11.7) v0.7.0
  # E ∈         {∞,           ☇,          ⊚,             ⊖,      BAD,   BIG}
  @type t :: :out_of_gas | :panic | :bad_exports | :oversize | :bad | :big

  # Formula (C.30) v0.6.6
  @codes %{out_of_gas: 1, panic: 2, bad_exports: 3, oversize: 4, bad: 5, big: 6}

  def code(error) do
    @codes[error]
  end

  def code_name(code) do
    Collections.key_for_value(@codes, code)
  end
end
