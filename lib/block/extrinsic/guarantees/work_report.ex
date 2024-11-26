defmodule Block.Extrinsic.Guarantee.WorkReport do
  @moduledoc """
  Work report
  section 11.1
  """

  alias Block.Extrinsic.{Assurance, AvailabilitySpecification, WorkItem}
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias Block.Extrinsic.WorkPackage
  alias PVM.RefineParams
  alias System.State.{CoreReport, Ready}
  alias Util.{Collections, Hash, MerkleTree, Time}

  use Codec.Encoder
  use MapUnion
  use SelectiveMock

  @type segment_root_lookup :: %{Types.hash() => Types.hash()}

  # Formula (118) v0.4.5
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

  # Formula (118) v0.4.5
  defstruct specification: %AvailabilitySpecification{},
            refinement_context: %RefinementContext{},
            core_index: 0,
            authorizer_hash: Hash.zero(),
            output: "",
            segment_root_lookup: %{},
            results: []

  # Formula (119) v0.4.5
  # ∀w ∈ W ∶ ∣wl ∣ ≤ 8 and ∣E(w)∣ ≤ WR
  @spec valid_size?(WorkReport.t()) :: boolean()
  def valid_size?(%__MODULE__{} = wr) do
    if wr.segment_root_lookup == %{} do
      true
    else
      map_size(wr.segment_root_lookup) + MapSet.size(wr.refinement_context.prerequisite) <= 8 and
        byte_size(e(wr)) <= Constants.max_work_report_size()
    end
  end

  @threadhold 2 * Constants.validator_count() / 3
  # Formula (11.15) v0.5.0 W ≡ [ ρ†[c]w | c <− NC, ∑a∈EA av[c] > 2/3V ]
  @spec available_work_reports(list(Assurance.t()), list(CoreReport.t())) :: list(t())
  mockable available_work_reports(assurances, core_reports_intermediate_1) do
    for c <- 0..(Constants.core_count() - 1),
        Enum.sum(for(a <- assurances, bits = Assurance.core_bits(a), do: Enum.at(bits, c))) >
          @threadhold do
      case Enum.at(core_reports_intermediate_1, c) do
        nil -> nil
        cr -> cr.work_report
      end
    end
  end

  def mock(:available_work_reports, _) do
    for i <- 0..(Constants.core_count() - 1), do: %WorkReport{core_index: i}
  end

  # Formula (165) v0.4.5
  # Formula (166) v0.4.5
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

  # Formula (167) v0.4.5

  @spec with_dependencies(__MODULE__.t()) :: {__MODULE__.t(), MapSet.t()}
  def with_dependencies(w) do
    {w, w.refinement_context.prerequisite ++ Utils.keys_set(w.segment_root_lookup)}
  end

  # Formula (168) v0.4.5
  @spec edit_queue(list({__MODULE__.t(), MapSet.t(Types.hash())}), MapSet.t(Types.hash())) ::
          list({__MODULE__.t(), MapSet.t(Types.hash())})
  def edit_queue(r, x) do
    for {w, d} <- r,
        w.specification.work_package_hash not in x do
      {w, d \\ x}
    end
  end

  # Formula (169) v0.4.5
  @spec accumulation_priority_queue(list({__MODULE__.t(), MapSet.t(Types.hash())})) ::
          list(__MODULE__.t())
  def accumulation_priority_queue(r) do
    case for {w, d} <- r, MapSet.size(d) == 0, do: w do
      [] -> []
      g -> g ++ accumulation_priority_queue(edit_queue(r, work_package_hashes(g)))
    end
  end

  # Formula (170) v0.4.5
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
    # Formula (163) v0.4.5
    accumulated = Collections.union(accumulation_history)

    # Formula (165) v0.4.5
    # Formula (166) v0.4.5
    {w_bang, w_q} = separate_work_reports(work_reports, accumulated)
    # Formula (171) v0.4.5
    m = Time.epoch_phase(block_timeslot)

    {before_m, after_m} = Enum.split(ready_to_accumulate, m)
    # Formula (173) v0.4.5
    q =
      edit_queue(
        for(x <- List.flatten(after_m ++ before_m), do: Ready.to_tuple(x)) ++ w_q,
        work_package_hashes(w_bang)
      )

    # Formula (172) v0.4.5
    w_bang ++ accumulation_priority_queue(q)
  end

  # Formula (201) v0.4.5
  @spec paged_proofs(list(Types.export_segment())) :: list(Types.export_segment())
  def paged_proofs(exported_segments) do
    segments_count = ceil(length(exported_segments) / 64)

    for i <- for(s <- 0..segments_count, do: 64 * s) do
      Utils.pad_binary_right(
        e({
          vs(MerkleTree.justification(exported_segments, i, 6)),
          vs(for x <- Enum.slice(exported_segments, i, 64), do: Hash.default(x))
        }),
        Constants.wswe()
      )
    end
  end

  # Formula (202) v0.4.5
  def compute_work_result(%WorkPackage{} = wp, core, services) do
    _l = calculate_segments(wp)
    # TODO
    d = %{}
    # TODO
    s = []

    case PVM.authorized(wp, core, services) do
      error when is_integer(error) ->
        error

      o ->
        # (r, ê) =T[(C(pw[j],r),e) ∣ (r,e) = I(p,j),j <− N∣pw∣]
        {r, e} =
          for j <- 0..(length(wp.work_items) - 1) do
            {result, exports} = process_item(wp, j, o, services)
            {WorkItem.to_work_result(Enum.at(wp.work_items, j), result), exports}
          end

        # Formula (206) v0.4.5
        specification =
          AvailabilitySpecification.from_package_execution(
            Hash.default(e(wp)),
            e(
              {wp, for(w <- wp, do: WorkItem.extrinsic_data(w, d)),
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
          # l # TODO
          segment_root_lookup: %{},
          results: r
        }
    end
  end

  # Formula (202) v0.4.5
  # I(p,j) ≡ΨR(wc,wg,ws,h,wy,px,pa,o,S(w,l),X(w),l)
  # and h = H(p), w = pw[j], l = ∑ pw[k]e
  def process_item(%WorkPackage{} = p, j, o, services) do
    w = Enum.at(p.work_items, j)
    h = Hash.default(e(p))
    l = Enum.sum(for k <- 0..(j - 1), do: Enum.at(p.work_items, k).export_count)
    pa = WorkPackage.implied_authorizer(p, services)

    PVM.refine(
      %RefineParams{
        service_code: w.code_hash,
        gas: w.gas_limit,
        service: w.service,
        work_package_hash: h,
        payload: w.payload,
        refinement_context: p.context,
        authorizer_hash: pa,
        output: o,
        # TODO
        import_segments: [],
        # TODO
        extrinsic_data: [],
        export_offset: l
      },
      services
    )

    # ...
  end

  defp calculate_segments(%WorkPackage{} = _wp) do
    # for w <- wp.work_items, do:
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
    # Formula (C.24) v0.5.0
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
    <<core_index::binary-size(2), bin::binary>> = bin
    <<authorizer_hash::binary-size(@hash_size), bin::binary>> = bin
    {output, bin} = VariableSize.decode(bin, :binary)
    {segment_root_lookup, bin} = VariableSize.decode(bin, :map, @hash_size, @hash_size)
    {results, rest} = VariableSize.decode(bin, WorkResult)

    {%__MODULE__{
       specification: specification,
       refinement_context: refinement_context,
       core_index: de_le(core_index, 2),
       segment_root_lookup: segment_root_lookup,
       authorizer_hash: authorizer_hash,
       output: output,
       results: results
     }, rest}
  end
end
