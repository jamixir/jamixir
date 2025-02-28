defmodule Block.Extrinsic.Guarantee.WorkReport do
  @moduledoc """
  Work report
  section 11.1
  """

  alias Block.Extrinsic.{Assurance, AvailabilitySpecification, WorkItem}
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias Block.Extrinsic.WorkPackage
  alias Codec.JsonEncoder
  alias System.State.{CoreReport, Ready}
  alias Util.{Collections, Hash, MerkleTree, Time}

  use Codec.Encoder
  use MapUnion
  use SelectiveMock

  @type segment_root_lookup :: %{Types.hash() => Types.hash()}

  # Formula (11.2) v0.6.0
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

  # Formula (11.2) v0.6.0
  defstruct specification: %AvailabilitySpecification{},
            refinement_context: %RefinementContext{},
            core_index: 0,
            authorizer_hash: Hash.zero(),
            output: "",
            segment_root_lookup: %{},
            results: []

  # Formula (11.3) v0.6.0
  # ∀w ∈ W ∶ ∣wl∣ +∣(wx)p∣ ≤ J
  @spec valid_size?(WorkReport.t()) :: boolean()
  def valid_size?(%__MODULE__{} = wr) do
    # Formula (11.3) v0.6.0
    # Formula (11.8) v0.6.0
    map_size(wr.segment_root_lookup) + MapSet.size(wr.refinement_context.prerequisite) <=
      Constants.max_work_report_dep_sum() and
      byte_size(wr.output) +
        Enum.sum(
          for %WorkResult{result: {_, o}} <- wr.results,
              do: byte_size(o)
        ) <=
        Constants.max_work_report_size()
  end

  @threadhold 2 * Constants.validator_count() / 3
  # Formula (11.16) v0.6.0 W ≡ [ ρ†[c]w | c <− NC, ∑a∈EA av[c] > 2/3V ]
  @spec available_work_reports(list(Assurance.t()), list(CoreReport.t())) :: list(t())
  mockable available_work_reports(assurances, core_reports_intermediate_1) do
    a_bits = for a <- assurances, do: Assurance.core_bits(a)

    for c <- 0..(Constants.core_count() - 1),
        Enum.sum(for(bits <- a_bits, do: elem(bits, c))) > @threadhold do
      case Enum.at(core_reports_intermediate_1, c) do
        nil -> nil
        cr -> cr.work_report
      end
    end
  end

  def mock(:available_work_reports, c) do
    if is_list(c[:core_reports_intermediate_1]) do
      for(
        cr <- c[:core_reports_intermediate_1],
        do: if(cr != nil, do: cr.work_report, else: %WorkReport{})
      )
    else
      for(i <- 0..(Constants.core_count() - 1), do: %WorkReport{core_index: i})
    end
  end

  # Formula (12.4) v0.6.0
  # Formula (12.5) v0.6.0
  @spec separate_work_reports(list(__MODULE__.t()), list(MapSet.t(Types.hash()))) ::
          {list(__MODULE__.t()), list({__MODULE__.t(), MapSet.t(Types.hash())})}
  def separate_work_reports(work_reports, accumulation_history)
      when is_list(accumulation_history),
      do: separate_work_reports(work_reports, Collections.union(accumulation_history))

  @spec separate_work_reports(list(__MODULE__.t()), MapSet.t(Types.hash())) ::
          {list(__MODULE__.t()), list({__MODULE__.t(), MapSet.t(Types.hash())})}
  def separate_work_reports(work_reports, accumulated) do
    {w_bang, pre_w_q} =
      Enum.split_with(work_reports, fn %WorkReport{
                                         refinement_context: wx,
                                         segment_root_lookup: wl
                                       } ->
        MapSet.size(wx.prerequisite) == 0 and Enum.empty?(wl)
      end)

    w_q = edit_queue(for(w <- pre_w_q, do: with_dependencies(w)), accumulated)
    {w_bang, w_q}
  end

  # Formula (12.6) v0.6.0
  @spec with_dependencies(__MODULE__.t()) :: {__MODULE__.t(), MapSet.t()}
  def with_dependencies(w) do
    {w, w.refinement_context.prerequisite ++ Utils.keys_set(w.segment_root_lookup)}
  end

  # Formula (12.7) v0.6.0
  @spec edit_queue(list({__MODULE__.t(), MapSet.t(Types.hash())}), MapSet.t(Types.hash())) ::
          list({__MODULE__.t(), MapSet.t(Types.hash())})
  def edit_queue(r, x) do
    for {w, d} <- r,
        w.specification.work_package_hash not in x do
      {w, d \\ x}
    end
  end

  # Formula (12.8) v0.6.0
  @spec accumulation_priority_queue(list({__MODULE__.t(), MapSet.t(Types.hash())})) ::
          list(__MODULE__.t())
  def accumulation_priority_queue(r) do
    case for {w, d} <- r, MapSet.size(d) == 0, do: w do
      [] -> []
      g -> g ++ accumulation_priority_queue(edit_queue(r, work_package_hashes(g)))
    end
  end

  # Formula (12.9) v0.6.0
  def work_package_hashes(work_reports) do
    for w <- work_reports, do: w.specification.work_package_hash, into: MapSet.new()
  end

  @spec accumulatable_work_reports(
          list(__MODULE__.t()),
          non_neg_integer(),
          list(MapSet.t(Types.hash())),
          list(list(Ready.t()))
        ) ::
          list(__MODULE__.t())
  def accumulatable_work_reports(
        work_reports,
        block_timeslot,
        accumulation_history,
        ready_to_accumulate
      ) do
    # Formula (12.2) v0.6.0
    accumulated = Collections.union(accumulation_history)

    # Formula (12.4) v0.6.0
    # Formula (12.5) v0.6.0
    {w_bang, w_q} = separate_work_reports(work_reports, accumulated)
    # Formula (12.10) v0.6.0
    m = Time.epoch_phase(block_timeslot)

    {before_m, after_m} = Enum.split(ready_to_accumulate, m)
    # Formula (12.12) v0.6.0
    q =
      edit_queue(
        for(x <- List.flatten(after_m ++ before_m), do: Ready.to_tuple(x)) ++ w_q,
        work_package_hashes(w_bang)
      )

    # Formula (12.11) v0.6.0
    w_bang ++ accumulation_priority_queue(q)
  end

  # Formula 14.10 v0.6.2
  @spec paged_proofs(list(Types.export_segment())) :: list(Types.export_segment())
  def paged_proofs(exported_segments) do
    segments_count = ceil(length(exported_segments) / 64)

    for i <- for(s <- 0..segments_count, do: 64 * s) do
      Utils.pad_binary_right(
        e({
          vs(MerkleTree.justification(exported_segments, i, 6)),
          vs(MerkleTree.justification_l(exported_segments, i, 6))
        }),
        Constants.segment_size()
      )
    end
  end

  # Formula (202) v0.4.5
  # TODO review to 14.11 v0.6.0
  def execute_work_package(%WorkPackage{} = wp, core, services) do
    s = []

    # o = ΨI (p,c)
    case PVM.authorized(wp, core, services) do
      error when is_integer(error) ->
        error

      o ->
        import_segments = for(w <- wp.work_items, do: WorkItem.import_segment_data(w, s))
        # (r, ê) =T[(C(pw[j],r),e) ∣ (r,e) = I(p,j),j <− N∣pw∣]
        {r, e} =
          for j <- 0..(length(wp.work_items) - 1) do
            {result, exports} = process_item(wp, j, o, import_segments, services, %{})
            {WorkItem.to_work_result(Enum.at(wp.work_items, j), result), exports}
          end

        # Formula (14.15) v0.6.0
        specification =
          AvailabilitySpecification.from_package_execution(
            Hash.default(e(wp)),
            e(
              {wp, for(w <- wp, do: WorkItem.extrinsic_data(w)),
               for(w <- wp, do: WorkItem.import_segment_data(w, s)),
               for(w <- wp, do: WorkItem.segment_justification(w, s))}
            ),
            e
          )

        %__MODULE__{
          authorizer_hash: WorkPackage.implied_authorizer(wp, services),
          output: o,
          refinement_context: nil,
          # s
          specification: specification,
          segment_root_lookup: get_import_segments(wp),
          results: r
        }
    end
  end

  use Sizes
  # Formula 14.11 v0.6.2
  # I(p,j) ≡ ...
  def process_item(%WorkPackage{} = p, j, o, import_segments, services, preimages) do
    w = Enum.at(p.work_items, j)
    # ℓ = ∑k<j pw[k]e
    l = p.work_items |> Enum.take(j) |> Enum.map(& &1.export_count) |> Enum.sum()
    # (r,e) = ΨR(j,p,o,i,ℓ)
    {r, e} = PVM.refine(j, p, o, import_segments, l, services, preimages)

    case {r, e} do
      # if ∣e∣= we
      {r, e} when length(e) == w.export_count ->
        {r, e}

      # otherwise if r ∈/ Y
      {r, _} when not is_binary(r) ->
        {r, zero_segments(w.export_count)}

      # otherwise
      _ ->
        {:bad_exports, zero_segments(w.export_count)}
    end
  end

  defp zero_segments(size), do: List.duplicate(<<0::@export_segment_size*8>>, size)

  # Formula (14.12) v0.6.2
  # TODO ⊞ part
  def segment_root(r) do
    r
  end

  # TODO 14.13 v0.6.2
  def get_import_segments(%WorkPackage{work_items: wi}) do
    %{}
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
      results: [WorkResult],
      segment_root_lookup: &decode_segment_root_lookup/1
    }
  end

  def to_json_mapping,
    do: %{
      specification: :package_spec,
      refinement_context: :context,
      output: :auth_output,
      segment_root_lookup:
        {:segment_root_lookup, &JsonEncoder.to_list(&1, :work_package_hash, :segment_tree_root)}
    }

  def decode_segment_root_lookup(json) do
    if json == nil do
      %{}
    else
      for i <- json,
          do:
            {JsonDecoder.from_json(i[:work_package_hash]),
             JsonDecoder.from_json(i[:segment_tree_root])},
          into: %{}
    end
  end

  defimpl Encodable do
    use Codec.Encoder
    # Formula (C.24) v0.6.0
    # E(xs,xx,xc,xa,↕xo,↕xl,↕xr)
    def encode(%WorkReport{} = wr) do
      e({
        wr.specification,
        wr.refinement_context,
        e_le(wr.core_index, 2),
        wr.authorizer_hash,
        vs(wr.output),
        wr.segment_root_lookup,
        vs(wr.results)
      })
    end
  end

  use Codec.Decoder
  use Sizes

  def decode(bin) do
    {specification, bin} = AvailabilitySpecification.decode(bin)
    {refinement_context, bin} = RefinementContext.decode(bin)
    <<core_index::16-little, bin::binary>> = bin
    <<authorizer_hash::binary-size(@hash_size), bin::binary>> = bin
    {output, bin} = VariableSize.decode(bin, :binary)
    {segment_root_lookup, bin} = VariableSize.decode(bin, :map, @hash_size, @hash_size)
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
