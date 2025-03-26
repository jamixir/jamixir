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
            exports: 0,
            # x
            extrinsic_count: 0,
            # z
            extrinsic_size: 0,
            # a
            accumulation: {0, 0},
            transfers: {0, 0}

  # Formula (13.7) v0.6.4
  @type t :: %__MODULE__{
          preimage: {non_neg_integer(), non_neg_integer()},
          refine: {non_neg_integer(), Types.gas()},
          imports: non_neg_integer(),
          exports: non_neg_integer(),
          extrinsic_count: non_neg_integer(),
          extrinsic_size: non_neg_integer(),
          accumulation: {non_neg_integer(), Types.gas()},
          transfers: {non_neg_integer(), Types.gas()}
        }

  # Formula (13.11) v0.6.4
  # Formula (13.12) v0.6.4
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
    # Formula (13.13) v0.6.4
    # Formula (13.15) v0.6.4
    refine_stats(available_work_reports)
    # Formula (13.11) v0.6.4
    |> accumulation_stats(accumulation_stats)
    |> deferred_transfers_stats(deferred_transfers_stats)
    # Formula (13.14) v0.6.4
    |> preimage_stats(preimages)
  end

  # Formula (13.14) v0.6.4 - p
  defp preimage_stats(previous_stats, preimages) do
    for %Preimage{service: s, blob: p} <- preimages, reduce: previous_stats do
      map ->
        Map.update(
          map,
          s,
          previous_stats[s] || %ServiceStatistic{preimage: {1, byte_size(p)}},
          fn stat ->
            {count, bytes} = stat.preimage
            %ServiceStatistic{stat | preimage: {count + 1, bytes + byte_size(p)}}
          end
        )
    end
  end

  # t
  defp deferred_transfers_stats(previous_stats, deferred_transfers_stats) do
    for {service, t_stat} <- deferred_transfers_stats, reduce: previous_stats do
      map ->
        Map.update(
          map,
          service,
          previous_stats[service] || %ServiceStatistic{transfers: t_stat},
          fn stat ->
            %ServiceStatistic{stat | transfers: t_stat}
          end
        )
    end
  end

  # a
  defp accumulation_stats(previous_stats, accumulation_stats) do
    for {service, acc_stat} <- accumulation_stats, reduce: previous_stats do
      map ->
        Map.update(
          map,
          service,
          previous_stats[service] || %ServiceStatistic{accumulation: acc_stat},
          &%ServiceStatistic{&1 | accumulation: acc_stat}
        )
    end
  end

  # i, x, z, e, r
  defp refine_stats(available_work_reports) do
    for w <- available_work_reports, w != nil, r <- w.results, reduce: %{} do
      map ->
        # put zeroed stats if not present
        map = Map.update(map, r.service, %ServiceStatistic{}, & &1)

        Map.update(map, r.service, %ServiceStatistic{}, fn previous ->
          {rn, ru} = previous.refine

          %ServiceStatistic{
            imports: previous.imports + r.imports,
            extrinsic_count: previous.extrinsic_count + r.extrinsic_count,
            extrinsic_size: previous.extrinsic_size + r.extrinsic_size,
            exports: previous.exports + r.exports,
            refine: {rn + 1, ru + r.gas_used}
          }
        end)
    end
  end
end
