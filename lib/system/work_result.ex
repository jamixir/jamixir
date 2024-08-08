defmodule System.WorkResult do
  @moduledoc """
  A module representing the result of a work-package, including the details of the service state alteration, code hash, payload hash, gas prioritization ratio, and output or error.
  """

  @type error :: :out_of_gas | :unexpected_termination | :bad_code | :code_too_large

  @type t :: %__MODULE__{
          # s: the index of the service whose state is to be altered and thus whose refine code was already executed
          service_index: non_neg_integer(),
          # c: hash of the code of the service at the time of being reported
          code_hash: Types.hash(),
          # l: the hash of the payload (l) within the work item which was executed in the refine stage to give this result
          payload_hash: Types.hash(),
          # g: the gas prioritization ratio used when determining how much gas should be allocated to execute this item’s accumulate
          gas_prioritization_ratio: non_neg_integer(),
          # o: the output or error of the execution of the code, which may be either an octet sequence in case it was successful, or a member of the set J if not
          output_or_error: binary() | error()
        }

  defstruct service_index: 0,
            code_hash: <<0::256>>,
            payload_hash: <<0::256>>,
            gas_prioritization_ratio: 0,
            output_or_error: <<>>
end
