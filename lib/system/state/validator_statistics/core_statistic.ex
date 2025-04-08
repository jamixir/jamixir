defmodule System.State.CoreStatistic do
  @moduledoc """
  Formula (13.6) v0.6.4
  """
  alias System.State.CoreStatistic
  alias Block.Extrinsic.{Assurance, Guarantee.WorkReport}

  defstruct da_load: 0,
            popularity: 0,
            imports: 0,
            exports: 0,
            extrinsic_count: 0,
            extrinsic_size: 0,
            bundle_size: 0,
            gas_used: 0

  @type t :: %__MODULE__{
          # d
          da_load: non_neg_integer(),
          # p
          popularity: non_neg_integer(),
          # i
          imports: non_neg_integer(),
          # e
          exports: non_neg_integer(),
          # z
          extrinsic_size: non_neg_integer(),
          # x
          extrinsic_count: non_neg_integer(),
          # b
          bundle_size: non_neg_integer(),
          # u
          gas_used: Types.gas()
        }

  @spec calculate_core_statistics(
          list(WorkReport.t()),
          list(WorkReport.t() | nil),
          list(Assurance.t())
        ) :: list(t())
  def calculate_core_statistics(incoming_work_reports, available_work_reports, assurances) do
    a_bits = Enum.map(assurances, &Assurance.core_bits/1)

    for c <- 0..(Constants.core_count() - 1) do
      w_incoming = Enum.at(incoming_work_reports, c, %{}) || %{}
      w_incoming_results = Map.get(w_incoming, :results)
      w_newly_available = Enum.at(available_work_reports, c, %{}) || %{}
      w_newly_available_specification = Map.get(w_newly_available, :specification, %{})

      %__MODULE__{
        # Formula (13.8) v0.6.4
        # Formula (13.9) v0.6.4
        imports: sum_field(w_incoming_results, :imports),
        exports: sum_field(w_incoming_results, :exports),
        extrinsic_count: sum_field(w_incoming_results, :extrinsic_count),
        extrinsic_size: sum_field(w_incoming_results, :extrinsic_size),
        gas_used: sum_field(w_incoming_results, :gas_used),
        bundle_size: (Map.get(w_incoming, :specification) || %{}) |> Map.get(:length, 0),
        # Formula (13.10) v0.6.4
        da_load:
          Map.get(w_newly_available_specification, :length, 0) +
            Constants.segment_size() *
              ceil(Map.get(w_newly_available_specification, :segment_count, 0) * (65 / 64)),
        popularity: sum_field(a_bits, c)
      }
    end
  end

  @spec sum_field(Enumerable.t(), atom() | non_neg_integer()) :: number()
  def sum_field(nil, _), do: 0

  def sum_field(enum, field) when is_atom(field),
    do: Enum.reduce(enum, 0, fn item, acc -> acc + Map.get(item, field, 0) end)

  def sum_field(enum, index) when is_integer(index) and index >= 0,
    do: Enum.reduce(enum, 0, fn item, acc -> acc + elem(item, index) end)

  def from_json(json_data) do
    %__MODULE__{
      da_load: json_data[:da_load] || 0,
      popularity: json_data[:popularity] || 0,
      bundle_size: json_data[:bundle_size] || 0,
      imports: json_data[:imports] || 0,
      exports: json_data[:exports] || 0,
      extrinsic_count: json_data[:extrinsic_count] || 0,
      extrinsic_size: json_data[:extrinsic_size] || 0,
      gas_used: json_data[:gas_used] || 0
    }
  end

  defimpl Encodable do
    use Codec.Encoder

    def encode(%CoreStatistic{} = c) do
      e(
        {c.da_load, c.popularity, c.imports, c.exports, c.extrinsic_size, c.extrinsic_count,
         c.bundle_size, c.gas_used}
      )
    end
  end
end
