defmodule Block.Extrinsic.Guarantee.WorkReport do
  @moduledoc """
  Work report
  section 11.1
  """
  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias Util.Hash
  use SelectiveMock

  # Formula (118) v0.4.1
  @type t :: %__MODULE__{
          # s
          specification: AvailabilitySpecification.t(),
          # x
          refinement_context: RefinementContext.t(),
          # c
          core_index: non_neg_integer(),
          # a
          authorizer_hash: Types.hash(),
          # o
          output: binary(),
          # l
          segment_root_lookup: %{Types.hash() => Types.hash()},
          # r
          results: list(WorkResult.t())
        }

  # Formula (118) v0.4.1
  defstruct specification: {},
            refinement_context: %RefinementContext{},
            core_index: 0,
            authorizer_hash: Hash.zero(),
            output: "",
            segment_root_lookup: MapSet.new(),
            results: []

  use Codec.Encoder
  # Formula (119) v0.4.1
  # ∀w ∈ W ∶ ∣wl ∣ ≤ 8 and ∣E(w)∣ ≤ WR
  @spec valid_size?(WorkReport.t()) :: boolean()
  def valid_size?(%__MODULE__{} = wr) do
    map_size(wr.segment_root_lookup) <= 8 and
      byte_size(e(wr)) <= Constants.max_work_report_size()
  end

  # Formula (130) v0.4.1 W ≡ [ ρ†[c]w | c <− NC, ∑a∈EA av[c] > 2/3V ]
  @spec available_work_reports(list(__MODULE__.t()), list(CoreReport.t())) :: list(WorkReport.t())
  mockable available_work_reports(assurances, core_reports_intermediate_1) do
    threshold = 2 * Constants.validator_count() / 3

    0..(Constants.core_count() - 1)
    |> Stream.filter(fn c ->
      Stream.map(assurances, &Utils.get_bit(&1.bitfield, c))
      |> Enum.sum() > threshold
    end)
    |> Stream.map(&Enum.at(core_reports_intermediate_1, &1).work_report)
    |> Enum.to_list()
  end

  def mock(:available_work_reports, _) do
    0..(Constants.core_count() - 1)
    |> Enum.map(fn i -> %WorkReport{core_index: i} end)
  end

  use JsonDecoder

  def json_mapping do
    %{
      specification: %{m: AvailabilitySpecification, f: :package_spec},
      refinement_context: %{m: RefinementContext, f: :context},
      output: :auth_output,
      results: [WorkResult]
    }
  end

  defimpl Encodable do
    use Codec.Encoder
    # Formula (307) v0.4.1
    # E(xs,xx,xc,xa,↕xo,↕xl,↕xr)
    def encode(%WorkReport{} = wr) do
      e(
        {wr.specification, wr.refinement_context, wr.core_index, vs(wr.segment_root_lookup),
         wr.authorizer_hash, vs(wr.output), vs(wr.results)}
      )
    end
  end
end
