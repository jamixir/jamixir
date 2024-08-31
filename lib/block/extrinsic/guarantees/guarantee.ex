defmodule Block.Extrinsic.Guarantee do
  @moduledoc """
  Work report guarantee.
  11.4
  Formula (138) v0.3.4
  """
  alias Block.Extrinsic.Guarantee.WorkReport

  # {validator_index, ed25519 signature}
  @type credential :: {Types.validator_index(), Types.ed25519_signature()}

  @type t :: %__MODULE__{
          # w
          work_report: WorkReport.t(),
          # t
          timeslot: non_neg_integer(),
          # a
          credential: credential()
        }

  defstruct work_report: %WorkReport{},
            timeslot: 0,
            credential: [{0, <<0::512>>}]

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee

    def encode(%Guarantee{}) do
      # TODO
    end
  end
end
