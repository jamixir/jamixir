defmodule System.State.AuthorizerQueue do
  @moduledoc """
  Formula (85) v0.3.4
  Represents the state of the authorizer queue.
  φ ∈ ⟦⟦H⟧∶Q⟧C, where H is the authorizers hash. Q is the size of the authorizations queue (max_authorization_queue_items).
  And C is the number of cores (core_count).
  """

  @type t :: %__MODULE__{
          queue: list(list(Types.hash()))
        }

  defstruct queue: [[]]
end
