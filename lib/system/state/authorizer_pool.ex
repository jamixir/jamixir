defmodule System.State.AuthorizerPool do
  @moduledoc """
  Formula (85) v0.3.4
  Represents the state of the authorizer pool.
  α ∈ ⟦⟦H⟧∶O⟧C, where H is the authorizers hash. O is the size of the authorizations pool (max_authorizations_items).
  And C is the number of cores (core_count).
  """

  @type t :: %__MODULE__{
          pool: list(list(Types.hash()))
        }

  defstruct pool: [[]]
end
