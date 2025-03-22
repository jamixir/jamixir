defmodule System.State.ServiceStatistic do
  alias Block.Extrinsic.Preimage
  alias System.State.ServiceStatistic
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

  # Formula (13.11) v0.6.4
  @spec calculate_stats(
          %{Types.service_index() => {}},
          list(AccumulationStatistic.t()),
          list(DefferedTransferStatistic.t()),
          list(Preimage.t())
        ) :: t
  def calculate_stats(
        available_work_reports,
        accumulation_stats,
        deferred_transfers_stats,
        preimages
      ) do
    refine_stats(available_work_reports)
    |> accumulation_stats(accumulation_stats)
    |> deferred_transfers_stats(deferred_transfers_stats)
    |> preimage_stats(preimages)
  end

  # p
  defp preimage_stats(previous_stats, preimages) do
    for %Preimage{service: s, blob: p} <- preimages, reduce: previous_stats do
      map ->
        Map.update(map, s, previous_stats[s] || %ServiceStatistic{}, fn stat ->
          {count, bytes} = stat.preimage
          %ServiceStatistic{stat | preimage: {count + 1, bytes + byte_size(p)}}
        end)
    end
  end

  # t
  defp deferred_transfers_stats(previous_stats, deferred_transfers_stats) do
    for {service, {count, total_gas}} <- deferred_transfers_stats, reduce: previous_stats do
      map ->
        Map.update(map, service, previous_stats[service] || %ServiceStatistic{}, fn stat ->
          %ServiceStatistic{stat | transfers: {count, total_gas}}
        end)
    end
  end

  # a
  defp accumulation_stats(previous_stats, accumulation_stats) do
    for {service, {total_gas, count}} <- accumulation_stats, reduce: previous_stats do
      map ->
        Map.update(map, service, previous_stats[service] || %ServiceStatistic{}, fn stat ->
          %ServiceStatistic{stat | accumulation: {total_gas, count}}
        end)
    end
  end

  # i, x, z, e, r
  defp refine_stats(available_work_reports) do
    for w <- available_work_reports, w != nil, r <- w.results, reduce: %{} do
      map ->
        Map.update(map, r.service, %ServiceStatistic{}, fn
          %ServiceStatistic{
            imports: i,
            extrinsics_count: x,
            extrinsics_size: z,
            refine: {rn, ru},
            exported_segments: e
          } ->
            %ServiceStatistic{
              imports: i + r.imports,
              extrinsics_count: x + r.extrinsics_count,
              extrinsics_size: z + r.extrinsics_size,
              exported_segments: e + r.exported_segments,
              refine: {rn + 1, ru + r.refine_gas}
            }
        end)
    end
  end
end
