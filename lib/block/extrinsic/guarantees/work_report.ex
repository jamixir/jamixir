defmodule Block.Extrinsic.Guarantee.WorkReport do
  @moduledoc """
  Work report
  section 11.1
  """
  alias Block.Extrinsic.{Assurance, AvailabilitySpecification}
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias System.State.{CoreReport, Ready, WorkPackageRootMap}
  alias Util.{Collections, Hash, Time}

  use SelectiveMock
  use MapUnion

  @type segment_root_lookup :: %{Types.hash() => Types.hash()}

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
          segment_root_lookup: segment_root_lookup(),
          # r
          results: list(WorkResult.t())
        }

  # Formula (118) v0.4.1
  defstruct specification: %AvailabilitySpecification{},
            refinement_context: %RefinementContext{},
            core_index: 0,
            authorizer_hash: Hash.zero(),
            output: "",
            segment_root_lookup: %{},
            results: []

  use Codec.Encoder
  # Formula (119) v0.4.1
  # ∀w ∈ W ∶ ∣wl ∣ ≤ 8 and ∣E(w)∣ ≤ WR
  @spec valid_size?(WorkReport.t()) :: boolean()
  def valid_size?(%__MODULE__{} = wr) do
    if wr.segment_root_lookup == nil do
      true
    else
      map_size(wr.segment_root_lookup) <= 8 and
        byte_size(e(wr)) <= Constants.max_work_report_size()
    end
  end

  # Formula (130) v0.4.1 W ≡ [ ρ†[c]w | c <− NC, ∑a∈EA av[c] > 2/3V ]
  @spec available_work_reports(list(Assurance.t()), list(CoreReport.t())) :: list(t())
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
    for i <- 0..(Constants.core_count() - 1), do: %WorkReport{core_index: i}
  end

  # Formula (161) v0.4.1
  # Formula (162) v0.4.1
  @spec separate_work_reports(list(__MODULE__.t()), list(segment_root_lookup())) ::
          {list(__MODULE__.t()), list({__MODULE__.t(), MapSet.t(Types.hash())})}
  def separate_work_reports(work_reports, accumulation_history)
      when is_list(accumulation_history),
      do: separate_work_reports(work_reports, Collections.union(accumulation_history))

  @spec separate_work_reports(list(__MODULE__.t()), segment_root_lookup()) ::
          {list(__MODULE__.t()), list({__MODULE__.t(), MapSet.t(Types.hash())})}
  def separate_work_reports(work_reports, accumulated) do
    {w_bang, pre_w_q} =
      Enum.split_with(work_reports, fn %WorkReport{
                                         refinement_context: wx,
                                         segment_root_lookup: wl
                                       } ->
        is_nil(wx.prerequisite) and Enum.empty?(wl)
      end)

    dependencies =
      for w <- pre_w_q do
        with_dependencies(w)
      end

    w_q = edit_queue(dependencies, accumulated)
    {w_bang, w_q}
  end

  # Formula (163) v0.4.1
  @spec with_dependencies(__MODULE__.t()) :: {__MODULE__.t(), MapSet.t()}
  def with_dependencies(w) do
    {w,
     (MapSet.new([w.refinement_context.prerequisite])
      |> MapSet.delete(nil)) ++ MapSet.new(Map.keys(w.segment_root_lookup))}
  end

  # Formula (164) v0.4.1
  @spec edit_queue(list({__MODULE__.t(), MapSet.t(Types.hash())}), WorkPackageRootMap.t()) ::
          list({__MODULE__.t(), MapSet.t(Types.hash())})
  def edit_queue(r, x) do
    x_keys = MapSet.new(Map.keys(x))

    for {w, d} <- r,
        w.specification.work_package_hash not in x_keys,
        x ++ w.segment_root_lookup == w.segment_root_lookup ++ x do
      {w, d \\ x_keys}
    end
  end

  # Formula (165) v0.4.1
  @spec accumulation_priority_queue(list({__MODULE__.t(), MapSet.t(Types.hash())}), %{
          Types.hash() => Types.hash()
        }) :: list(__MODULE__.t())
  def accumulation_priority_queue(r, a) do
    g = for {w, d} <- r, MapSet.size(d) == 0, do: w

    if Enum.empty?(g) do
      []
    else
      g_map = WorkPackageRootMap.create(g)
      g ++ accumulation_priority_queue(edit_queue(r, g_map), Map.merge(a, g_map))
    end
  end

  # Formula (168) v0.4.1
  @spec accumulatable_work_reports(
          list(__MODULE__.t()),
          non_neg_integer(),
          list(WorkPackageRootMap.t()),
          list(list(Ready.t()))
        ) ::
          list(__MODULE__.t())
  def accumulatable_work_reports(
        work_reports,
        block_timeslot,
        accumulation_history,
        ready_to_accumulate
      ) do
    # Formula (159) v0.4.1
    accumulated = Collections.union(accumulation_history)

    # Formula (162) v0.4.1
    {w_bang, w_q} = separate_work_reports(work_reports, accumulated)
    # Formula (167) v0.4.1
    m = Time.epoch_phase(block_timeslot)

    {before_m, rest} = Enum.split(ready_to_accumulate, m)

    # Formula (168) v0.4.1
    # this has changed after v0.4.1
    w_bang ++
      accumulation_priority_queue(
        for(x <- List.flatten(before_m ++ rest), do: Ready.to_tuple(x)) ++ w_q,
        accumulated
      )
  end

  use JsonDecoder

  @spec json_mapping() :: %{
          output: :auth_output,
          refinement_context: %{f: :context, m: RefinementContext},
          results: [Block.Extrinsic.Guarantee.WorkResult, ...],
          specification: %{f: :package_spec, m: Block.Extrinsic.AvailabilitySpecification}
        }
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
      e({
        wr.specification,
        wr.refinement_context,
        wr.core_index,
        case wr.segment_root_lookup do
          nil -> <<0>>
          a -> a
        end,
        wr.authorizer_hash,
        vs(wr.output),
        vs(wr.results)
      })
    end
  end

  use Codec.Decoder
  use Sizes

  def decode(bin) do
    {specification, bin} = AvailabilitySpecification.decode(bin)
    {refinement_context, bin} = RefinementContext.decode(bin)
    <<core_index::8, bin::binary>> = bin
    {segment_root_lookup, bin} = VariableSize.decode(bin, :map, @hash_size, @hash_size)

    segment_root_lookup =
      if segment_root_lookup == %{} do
        nil
      else
        segment_root_lookup
      end

    <<authorizer_hash::binary-size(@hash_size), bin::binary>> = bin
    {output, bin} = VariableSize.decode(bin, :binary)
    {results, rest} = VariableSize.decode(bin, WorkResult)

    {%__MODULE__{
       specification: specification,
       refinement_context: refinement_context,
       core_index: core_index,
       segment_root_lookup: segment_root_lookup,
       authorizer_hash: authorizer_hash,
       output: output,
       results: results
     }, rest}
  end
end
