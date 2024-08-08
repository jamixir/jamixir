defmodule Block.Extrinsic.Disputes.ProcessedVerdict do
  @moduledoc """
  Struct to hold processed verdict information.
  """
  alias Types

  defstruct [
    # The hash of the work report
    :work_report_hash,
    # The identifier for the validator set (:current or :previous)
    :validator_set_id,
    # The number of judgements
    :judgements_count,
    # The size of the validator set
    :validator_set_size,
    # The number of positive votes
    :positive_votes,
    # The classification of the verdict (:good, :bad, :wonky)
    :classification
  ]

  @type t :: %__MODULE__{
          work_report_hash: Types.hash(),
          validator_set_id: :current | :previous,
          judgements_count: non_neg_integer(),
          validator_set_size: non_neg_integer(),
          positive_votes: non_neg_integer(),
          classification: :good | :bad | :wonky
        }
end
