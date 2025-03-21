defmodule System.State.ServiceStatistic do
  alias Block.Extrinsic
  # p
  defstruct preimage: {0, 0},
            # r
            refine: {0, 0},
            # i
            imports: 0,
            # e
            exported_segments: 0,
            # x
            extrinsics_count: 0,
            # z
            extrinsics_size: 0,
            # a
            accumulation: {0, 0},
            transfers: {0, 0}

  # Formula (13.7) v0.6.4
  @type t :: %__MODULE__{
          preimage: {non_neg_integer(), non_neg_integer()},
          refine: {non_neg_integer(), Types.gas()},
          imports: non_neg_integer(),
          exported_segments: non_neg_integer(),
          extrinsics_count: non_neg_integer(),
          extrinsics_size: non_neg_integer(),
          accumulation: {non_neg_integer(), Types.gas()},
          transfers: {non_neg_integer(), Types.gas()}
        }

  # Formula (13.13) v0.6.4
  def work_results_services(work_reports) do
    for w <- work_reports, r <- w.results, do: r.service, into: MapSet.new()
  end

  # Formula (13.14) v0.6.4
  def preimage_services(%Extrinsic{preimages: preimages}) do
    for preimage <- preimages, do: preimage.service, into: MapSet.new()
  end

  # Formula (13.11)
  def calculate_stats(
        available_work_reports,
        accumulation_stats,
        deffered_transfers_stats
      ) do
  end
end
