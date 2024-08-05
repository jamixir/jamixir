defmodule Disputes.ProcessedVerdict do
  @moduledoc """
  Struct to hold processed verdict information.
  """
  alias Types

  defstruct [
    :work_report_hash,  # The hash of the work report
    :validator_set_id,  # The identifier for the validator set (:current or :previous)
    :judgements_count,  # The number of judgements
    :validator_set_size, # The size of the validator set
    :positive_votes,    # The number of positive votes
    :classification     # The classification of the verdict (:good, :bad, :wonky)
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
