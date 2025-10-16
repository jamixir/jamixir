defmodule Block.Extrinsic.Guarantee.WorkReport do
  alias System.State.ServiceAccount
  alias Block.Extrinsic.{Assurance, AvailabilitySpecification}
  alias Block.Extrinsic.Guarantee.{WorkDigest, WorkReport}
  alias Block.Extrinsic.{WorkItem, WorkPackage}
  alias Codec.{JsonEncoder, VariableSize}
  alias System.State.{CoreReport, Ready}
  alias Util.{Collections, Hash, MerkleTree, Time}
  import Codec.{Decoder, Encoder}
  use MapUnion
  use SelectiveMock

  @type segment_root_lookup :: %{Types.hash() => Types.hash()}

  # Formula (11.2) v0.7.2
  @type t :: %__MODULE__{
          # s
          specification: AvailabilitySpecification.t(),
          # c
          refinement_context: RefinementContext.t(),
          # c
          core_index: non_neg_integer(),
          # a
          authorizer_hash: Types.hash(),
          # t
          output: binary(),
          # l
          segment_root_lookup: segment_root_lookup(),
          # d
          digests: list(WorkDigest.t()),
          # g
          auth_gas_used: Types.gas()
        }

  # Formula (11.2) v0.7.2
  defstruct specification: %AvailabilitySpecification{},
            refinement_context: %RefinementContext{},
            core_index: 0,
            authorizer_hash: Hash.zero(),
            output: "",
            segment_root_lookup: %{},
            digests: [],
            auth_gas_used: 0

  # Formula (11.3) v0.7.2
  # ∀r ∈ R ∶ ∣rl∣ +∣(rc)p∣ ≤ J
  @spec valid_size?(WorkReport.t()) :: boolean()
  def valid_size?(%__MODULE__{} = wr) do
    # Formula (11.3) v0.7.2
    # Formula (11.8) v0.7.2
    # ∀r ∈ R ∶∣rt∣ + ∑∣dl∣ ≤ WR
    map_size(wr.segment_root_lookup) + MapSet.size(wr.refinement_context.prerequisite) <=
      Constants.max_work_report_dep_sum() and
      byte_size(wr.output) +
        Enum.sum(
          for %WorkDigest{result: {_, o}} <- wr.digests,
              do: if(is_atom(o), do: 0, else: byte_size(o))
        ) <=
        Constants.max_work_report_size()
  end

  @threadhold 2 * Constants.validator_count() / 3
  # Formula (11.16) v0.7.2 R ≡ [ ρ†[c]r | c <−ℕ_C, ∑a∈EA af[c] > 2/3V ]
  @spec available_work_reports(list(Assurance.t()), list(CoreReport.t())) :: list(t() | nil)
  mockable available_work_reports(assurances, core_reports_intermediate_1) do
    a_bits = Enum.map(assurances, &Assurance.core_bits/1)

    for c <- 0..(Constants.core_count() - 1),
        Enum.sum(for(bits <- a_bits, do: elem(bits, c))) > @threadhold do
      case Enum.at(core_reports_intermediate_1, c) do
        nil -> nil
        cr -> cr.work_report
      end
    end
  end

  # Formula (17.1) v0.7.2
  # Formula (17.2) v0.7.2
  @spec auditable_work_reports(list(Assurance.t()), list(CoreReport.t()), list(CoreReport.t())) ::
          list(t() | nil)
  def auditable_work_reports(assurances, core_reports_intermediate_1, core_reports) do
    available = available_work_reports(assurances, core_reports_intermediate_1)
    for r <- core_reports, do: if(Enum.member?(available, r), do: r, else: nil)
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

  # Formula (12.4) v0.7.2
  # Formula (12.5) v0.7.2
  @spec separate_work_reports(list(__MODULE__.t()), list(MapSet.t(Types.hash()))) ::
          {list(__MODULE__.t()), list({__MODULE__.t(), MapSet.t(Types.hash())})}
  def separate_work_reports(work_reports, accumulation_history)
      when is_list(accumulation_history),
      do: separate_work_reports(work_reports, Collections.union(accumulation_history))

  @spec separate_work_reports(list(__MODULE__.t()), MapSet.t(Types.hash())) ::
          {list(__MODULE__.t()), list({__MODULE__.t(), MapSet.t(Types.hash())})}
  def separate_work_reports(work_reports, accumulated) do
    {immediate_work_reports, pre_w_q} =
      Enum.split_with(work_reports, fn %WorkReport{
                                         refinement_context: wc,
                                         segment_root_lookup: wl
                                       } ->
        MapSet.size(wc.prerequisite) == 0 and Enum.empty?(wl)
      end)

    queued_work_reports =
      Enum.map(pre_w_q, &with_dependencies/1) |> filter_and_update_dependencies(accumulated)

    {immediate_work_reports, queued_work_reports}
  end

  # Formula (12.6) v0.7.2
  @spec with_dependencies(__MODULE__.t()) :: {__MODULE__.t(), MapSet.t()}
  def with_dependencies(w) do
    {w, w.refinement_context.prerequisite ++ Utils.keys_set(w.segment_root_lookup)}
  end

  # Formula (12.7) v0.7.2
  @spec filter_and_update_dependencies(
          list({__MODULE__.t(), MapSet.t(Types.hash())}),
          MapSet.t(Types.hash())
        ) ::
          list({__MODULE__.t(), MapSet.t(Types.hash())})
  def filter_and_update_dependencies(r, x) do
    for {w, d} <- r,
        w.specification.work_package_hash not in x do
      {w, d \\ x}
    end
  end

  # Formula (12.8) v0.7.2
  @spec accumulation_priority_queue(list({__MODULE__.t(), MapSet.t(Types.hash())})) ::
          list(__MODULE__.t())
  def accumulation_priority_queue(r) do
    g = for {w, d} <- r, MapSet.size(d) == 0, do: w

    case g do
      [] ->
        []

      g ->
        g ++
          accumulation_priority_queue(filter_and_update_dependencies(r, work_package_hashes(g)))
    end
  end

  # Formula (12.9) v0.7.2
  @spec work_package_hashes(list(__MODULE__.t())) :: MapSet.t(Types.hash())
  def work_package_hashes(work_reports) do
    for r <- work_reports, do: r.specification.work_package_hash, into: MapSet.new()
  end

  # Formula (12.11) v0.7.2 (R*)
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
    # Formula (12.2) v0.7.2
    accumulated = Collections.union(accumulation_history)

    # Formula (12.4) v0.7.2
    # Formula (12.5) v0.7.2
    {immediate_work_reports, queued_work_reports} =
      separate_work_reports(work_reports, accumulated)

    # Formula (12.10) v0.7.2
    m = Time.epoch_phase(block_timeslot)

    {before_m, after_m} = Enum.split(ready_to_accumulate, m)
    # Formula (12.12) v0.7.2
    q =
      (for(x <- List.flatten(after_m ++ before_m), do: Ready.to_tuple(x)) ++ queued_work_reports)
      |> filter_and_update_dependencies(work_package_hashes(immediate_work_reports))

    # Formula (12.11) v0.7.2
    immediate_work_reports ++ accumulation_priority_queue(q)
  end

  # Formula (14.11) v0.7.2
  @spec paged_proofs(list(Types.export_segment())) :: list(Types.export_segment())
  def paged_proofs(exports) do
    segments_count = ceil(length(exports) / 64)

    for i <- for(s <- 0..segments_count, do: 64 * s) do
      Utils.pad_binary_right(
        e({
          vs(MerkleTree.justification(exports, i, 6)),
          vs(MerkleTree.justification_l(exports, i, 6))
        }),
        Constants.segment_size()
      )
    end
  end

  # Formula (14.12) v0.7.2
  @spec execute_work_package(WorkPackage.t(), list(list(binary())), integer(), %{
          integer() => ServiceAccount.t()
        }) ::
          :error | Task.t({WorkReport.t(), list(binary())})
  def execute_work_package(%WorkPackage{} = wp, extrinsics, core, services) do
    # {t, g} = ΨI (p,c)
    w_r = Constants.max_work_report_size()

    case PVM.authorized(wp, core, services) do
      {t, _} when is_atom(t) or byte_size(t) > w_r ->
        :error

      {t, _gas_used} ->
        segments_data = for(w <- wp.work_items, do: WorkItem.import_segment_data(w))
        import_segments = for(w <- segments_data, do: for(s <- w, do: s.data))

        {import_segments,
         Task.async(fn -> refine(wp, extrinsics, core, t, services, import_segments) end)}
    end
  end

  @spec refine(
          WorkPackage.t(),
          list(list(binary())),
          integer(),
          binary(),
          %{integer() => ServiceAccount.t()},
          list(list(binary()))
        ) ::
          {WorkReport.t(), list(binary())}
  defp refine(wp, extrinsics, core, o, services, import_segments) do
    # (d, ê) =T[(C(pw[j],r),e) ∣ (r,e) = I(p,j),j <− N∣pw∣]
    {d, e} =
      for j <- 0..(length(wp.work_items) - 1) do
        # (r,u,e) = I(p,j)
        {result, gas, exports} = process_item(wp, j, o, import_segments, services, extrinsics)
        # C(pw [j],r), e)
        {WorkItem.to_work_digest(Enum.at(wp.work_items, j), result, gas), exports}
      end
      |> Enum.unzip()

    exports = List.flatten(e)

    # Formula (14.16) v0.7.2
    s =
      AvailabilitySpecification.from_execution(
        h(e(wp)),
        WorkPackage.bundle_binary(wp),
        exports
      )

    {%__MODULE__{
       specification: s,
       refinement_context: wp.context,
       core_index: core,
       authorizer_hash: WorkPackage.implied_authorizer(wp, services),
       output: o,
       segment_root_lookup: get_segment_lookup_dict(wp),
       digests: d
     }, exports}
  end

  def process_item(%WorkPackage{} = p, j, o, import_segments, services, extrinsics) do
    w = Enum.at(p.work_items, j)
    # ℓ = ∑k<j pw[k]e
    l = p.work_items |> Enum.take(j) |> Enum.map(& &1.export_count) |> Enum.sum()
    # (r,e) = ΨR(j,p,o,i,ℓ)
    {r, e, u} = PVM.refine(j, p, o, import_segments, l, services, extrinsics)

    case {r, e, u} do
      # First, check export count
      {_, e, u} when length(e) != w.export_count ->
        {:bad_exports, u, zero_segments(w.export_count)}

      # Then, check if r is binary
      {r, _, u} when not is_binary(r) ->
        {r, u, zero_segments(w.export_count)}

      # Then, check size
      {r, _, u} ->
        # optimization note: this is probably expensive, can cache maybe?
        z =
          byte_size(o) +
            if j == 0 do
              0
            else
              Enum.sum(
                for k <- 0..(j - 1) do
                  {r_k, _, _} = process_item(p, k, o, import_segments, services, extrinsics)
                  if is_binary(r_k), do: byte_size(r_k), else: 0
                end
              )
            end

        if byte_size(r) + z > Constants.max_work_report_size() do
          {:oversize, u, zero_segments(w.export_count)}
        else
          {r, u, e}
        end
    end
  end

  defp zero_segments(size), do: List.duplicate(<<0::m(export_segment)>>, size)

  # Formula (14.13) v0.7.2
  def segment_root({:tagged_hash, r}), do: Storage.get_segments_root(r)
  def segment_root(r), do: r

  # Formula (14.13) v0.7.2
  def get_segment_lookup_dict(%WorkPackage{work_items: wi}) do
    for w <- wi,
        {{:tagged_hash, wp_hash} = r, _} <- w.import_segments,
        s = segment_root(r),
        s != nil do
      {wp_hash, s}
    end
    |> Enum.uniq()
    |> Enum.take(8)
    |> Map.new()
  end

  use JsonDecoder

  @spec json_mapping() :: %{
          output: :auth_output,
          refinement_context: %{f: :context, m: RefinementContext},
          results: [Block.Extrinsic.Guarantee.WorkDigest, ...],
          specification: %{f: :package_spec, m: Block.Extrinsic.AvailabilitySpecification}
        }
  def json_mapping do
    %{
      specification: %{m: AvailabilitySpecification, f: :package_spec},
      refinement_context: %{m: RefinementContext, f: :context},
      output: :auth_output,
      digests: [[WorkDigest], :results],
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
    import Codec.Encoder
    # Formula (C.27) v0.7.2
    # E(r_s,r_c,r_c,r_a,r_g,↕r_t,↕r_l,↕r_d)
    def encode(%WorkReport{} = wr) do
      e({
        wr.specification,
        wr.refinement_context,
        wr.core_index,
        wr.authorizer_hash,
        wr.auth_gas_used,
        vs(wr.output),
        wr.segment_root_lookup,
        vs(wr.digests)
      })
    end
  end

  use Sizes

  def decode(bin) do
    {specification, bin} = AvailabilitySpecification.decode(bin)
    {refinement_context, bin} = RefinementContext.decode(bin)
    {core_index, bin} = de_i(bin)
    <<authorizer_hash::b(hash), bin::binary>> = bin
    {auth_gas_used, bin} = de_i(bin)
    {output, bin} = VariableSize.decode(bin, :binary)
    {segment_root_lookup, bin} = VariableSize.decode(bin, :map, @hash_size, @hash_size)
    {digests, rest} = VariableSize.decode(bin, WorkDigest)

    {%__MODULE__{
       specification: specification,
       refinement_context: refinement_context,
       core_index: core_index,
       segment_root_lookup: segment_root_lookup,
       authorizer_hash: authorizer_hash,
       output: output,
       digests: digests,
       auth_gas_used: auth_gas_used
     }, rest}
  end
end
