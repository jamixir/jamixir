defmodule Block.Extrinsics.Guarantee do
  alias System.WorkReport
  alias Types

  # {validator_index, ed25519 signature}
  @type credential :: {Types.validator_index(), Types.ed25519_signature()}

  @type t :: %__MODULE__{
          # E_g
          work_report: WorkReport.t(),
          timeslot: non_neg_integer(),
          credential: credential()
        }

  defstruct core_index: 0,
            work_report: %WorkReport{},
            timeslot: 0,
            credential: {0, <<0::512>>}
end
