defmodule System.State.CoreStatistic do
  @moduledoc """
  Formula (13.6) v0.6.4
  """
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee.WorkReport
  import Enum

  defstruct data_size: 0,
            p: 0,
            imports: 0,
            exported_segments: 0,
            extrinsics_count: 0,
            extrinsics_size: 0,
            bundle_length: 0,
            refine_gas: 0

  @type t :: %__MODULE__{
          data_size: non_neg_integer(),
          p: non_neg_integer(),
          bundle_length: non_neg_integer(),
          # i
          imports: non_neg_integer(),
          # e
          exported_segments: non_neg_integer(),
          # x
          extrinsics_count: non_neg_integer(),
          # z
          extrinsics_size: non_neg_integer(),
          # u
          refine_gas: Types.gas()
        }

  @spec calculate_core_statistics(list(WorkReport.t() | nil), list(Assurance.t())) :: list(t())
  def calculate_core_statistics(available_work_reports, assurances) do
    a_bits = for a <- assurances, do: Assurance.core_bits(a)

    for {w, c} <- Enum.with_index(available_work_reports) do
      if w == nil do
        %__MODULE__{}
      else
        %__MODULE__{
          # Formula 13.8 v0.6.4
          # Formula 13.9 v0.6.4
          imports: sum(for(r <- w.results, do: r.imports)),
          exported_segments: sum(for(r <- w.results, do: r.exported_segments)),
          extrinsics_count: sum(for(r <- w.results, do: r.extrinsics_count)),
          extrinsics_size: sum(for(r <- w.results, do: r.extrinsics_size)),
          refine_gas: sum(for(r <- w.results, do: r.refine_gas)),
          bundle_length: w.specification.length,
          # Formula 13.10 v0.6.4
          data_size:
            w.specification.length +
              Constants.segment_size() * ceil(w.specification.segment_count * (65 / 64)),
          p: sum(for(bits <- a_bits, do: elem(bits, c)))
        }
      end
    end
  end
end
