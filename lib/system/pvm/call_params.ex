defmodule System.PVM.CallParams do
  @moduledoc """
  This module is responsible for handling the call parameters for the PVM.
  """
  alias System.PVM.Memory

  # Formula (32) v0.3.4
  @type t :: %__MODULE__{
          # p
          program: binary(),
          # ı - register
          register: Types.register_value(),
          # ξ - gas
          gas: Types.gas(),
          # ω
          registers: list(Types.register_value()),
          # μ
          memory: Memory.t()
        }

  defstruct program: <<>>,
            register: 0,
            gas: 0,
            registers: List.duplicate(0, 13),
            memory: %Memory{}
end
