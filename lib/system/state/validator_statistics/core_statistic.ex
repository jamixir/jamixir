defmodule System.State.CoreStatistic do
  @moduledoc """
  Formula (13.6) v0.6.4
  """
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee.WorkReport
  import Enum

  defstruct da_load: 0,
            popularity: 0,
            imports: 0,
            exports: 0,
            extrinsic_count: 0,
            extrinsic_size: 0,
            bundle_size: 0,
            gas_used: 0

  @type t :: %__MODULE__{
          da_load: non_neg_integer(),
          popularity: non_neg_integer(),
          bundle_size: non_neg_integer(),
          # i
          imports: non_neg_integer(),
          # e
          exports: non_neg_integer(),
          # x
          extrinsic_count: non_neg_integer(),
          # z
          extrinsic_size: non_neg_integer(),
          # u
          gas_used: Types.gas()
        }

  @spec calculate_core_statistics(list(WorkReport.t() | nil), list(Assurance.t())) :: list(t())
  def calculate_core_statistics(available_work_reports, assurances) do
    a_bits = Enum.map(assurances, &Assurance.core_bits/1)

    for {w, c} <- Enum.with_index(available_work_reports) do
      if w == nil do
        %__MODULE__{}
      else
        %__MODULE__{
          # Formula 13.8 v0.6.4
          # Formula 13.9 v0.6.4
          imports: sum(for(r <- w.results, do: r.imports)),
          exports: sum(for(r <- w.results, do: r.exports)),
          extrinsic_count: sum(for(r <- w.results, do: r.extrinsic_count)),
          extrinsic_size: sum(for(r <- w.results, do: r.extrinsic_size)),
          gas_used: sum(for(r <- w.results, do: r.gas_used)),
          bundle_size: w.specification.length,
          # Formula 13.10 v0.6.4
          da_load:
            w.specification.length +
              Constants.segment_size() * ceil(w.specification.segment_count * (65 / 64)),
          popularity: sum(for(bits <- a_bits, do: elem(bits, c)))
        }
      end
    end
  end
end
