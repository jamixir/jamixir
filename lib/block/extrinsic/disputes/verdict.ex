defmodule Block.Extrinsic.Disputes.Verdict do
  @moduledoc """
  Formula 98 v0.3.4
  verdic on the correctness of a work-report.
  the Dispute extrinsic Ed may contain 1 or more verdicts. secion 10.2
  A verdict consists of a work-report hash, an epoch index, and a list of judgements from validators.
  """

  alias Types
  alias Block.Extrinsic.Disputes.Judgement

  @type t :: %__MODULE__{
          work_report_hash: Types.hash(),
          epoch_index: Types.epoch_index(),
          judgements: list(Judgement.t())
        }

  defstruct work_report_hash: <<>>, epoch_index: 0, judgements: []
end
