defmodule System.State.ServiceStatistic do
  alias Block.Extrinsic.Preimage
  alias System.State.ServiceStatistic
  alias Block.Extrinsic.Guarantee.WorkReport

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

  # Formula (13.7) v0.6.5
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

  # Formula (13.11) v0.6.5
  # Formula (13.12) v0.6.5
  @spec calculate_stats(
          list(WorkReport.t()),
          list(AccumulationStatistic.t()),
          list(DefferedTransferStatistic.t()),
          list(Preimage.t())
        ) :: t
  def calculate_stats(
        incoming_work_reports,
        accumulation_stats,
        deferred_transfers_stats,
        preimages
      ) do
    # Formula (13.13) v0.6.5
    # Formula (13.15) v0.6.5
    refine_stats(incoming_work_reports)
    # Formula (13.11) v0.6.5
    |> accumulation_stats(accumulation_stats)
    |> deferred_transfers_stats(deferred_transfers_stats)
    # Formula (13.14) v0.6.5
    |> preimage_stats(preimages)
  end

  # Formula (13.14) v0.6.5 - p
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
  defp refine_stats(incoming_work_reports) do
    for w <- incoming_work_reports, w != nil, d <- w.digests, reduce: %{} do
      map ->
        # put zeroed stats if not present
        map = Map.update(map, d.service, %ServiceStatistic{}, & &1)

        Map.update(map, d.service, %ServiceStatistic{}, fn previous ->
          {rn, ru} = previous.refine

          %ServiceStatistic{
            imports: previous.imports + d.imports,
            extrinsic_count: previous.extrinsic_count + d.extrinsic_count,
            extrinsic_size: previous.extrinsic_size + d.extrinsic_size,
            exports: previous.exports + d.exports,
            refine: {rn + 1, ru + d.gas_used}
          }
        end)
    end
  end

  def from_json(json_data) do
    %__MODULE__{
      preimage: {json_data[:provided_count] || 0, json_data[:provided_size] || 0},
      refine: {json_data[:refinement_count] || 0, json_data[:refinement_gas_used] || 0},
      imports: json_data[:imports] || 0,
      exports: json_data[:exports] || 0,
      extrinsic_count: json_data[:extrinsic_count] || 0,
      extrinsic_size: json_data[:extrinsic_size] || 0,
      accumulation: {json_data[:accumulate_count] || 0, json_data[:accumulate_gas_used] || 0},
      transfers: {json_data[:on_transfers_count] || 0, json_data[:on_transfers_gas_used] || 0}
    }
  end

  def to_json_mapping do
    %{
      preimage: [:provided_count, :provided_size],
      refine: [:refinement_count, :refinement_gas_used],
      accumulation: [:accumulate_count, :accumulate_gas_used],
      transfers: [:on_transfers_count, :on_transfers_gas_used]
    }
  end

  defimpl Encodable do
    use Codec.Encoder

    def encode(%ServiceStatistic{} = c) do
      e({
        c.preimage,
        c.refine,
        c.imports,
        c.exports,
        c.extrinsic_size,
        c.extrinsic_count,
        c.accumulation,
        c.transfers
      })
    end
  end
end
