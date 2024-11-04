defmodule System.PVM.SingleStep.CallParams do

  alias System.PVM.Memory

  # Formula (241) v0.4.5
  @type t :: %__MODULE__{
          # c
          instruction: binary(),
          # k
          bitmask: bitstring(),
          # j
          jump_table: list(non_neg_integer()),
          # ı - register
          register: Types.register_value(),
          # ξ - gas
          gas: Types.gas(),
          # ω
          registers: list(Types.register_value()),
          # μ
          memory: Memory.t()
        }

  defstruct instruction: <<>>,
            bitmask: <<>>,
            jump_table: [],
            register: 0,
            gas: 0,
            registers: List.duplicate(0, 13),
            memory: %Memory{}
end
