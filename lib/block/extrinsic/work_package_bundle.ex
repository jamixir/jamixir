defmodule Block.Extrinsic.WorkPackageBundle do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.DataAvailability.SegmentData
  alias Block.Extrinsic.WorkPackage
  import Codec.Encoder

  @type t :: %__MODULE__{
          work_package: Block.Extrinsic.WorkPackage.t(),
          import_segments: list(System.DataAvailability.SegmentData.t()),
          justifications: list(System.DataAvailability.JustificationData.t()),
          extrinsics: list(binary())
        }

  defstruct work_package: %Block.Extrinsic.WorkPackage{},
            import_segments: [],
            justifications: [],
            extrinsics: []

  defimpl Encodable do
    alias Block.Extrinsic.WorkPackageBundle
    import Codec.Encoder

    # Formula (14.16) v0.7.2
    def encode(%WorkPackageBundle{} = b) do
      e({b.work_package, b.import_segments, b.justifications, b.extrinsics})
    end
  end

  def decode(bin) do
    {work_package, bin} = WorkPackage.decode(bin)

    {import_segments, bin} =
      for wi <- work_package.work_items, reduce: {[], bin} do
        {import_segments, bin} ->
          {wi_segments, rest} =
            for {r, n} <- wi.import_segments,
                root = WorkReport.segment_root(r),
                reduce: {[], bin} do
              {wi_segments, bin} ->
                <<data::b(export_segment), rest::binary>> = bin

                {wi_segments ++ [%SegmentData{merkle_root: root, segment_index: n, data: data}],
                 rest}
            end

          {import_segments ++ [wi_segments], rest}
      end

    {justifications, bin} =
      for wi <- work_package.work_items, reduce: {[], bin} do
        {justifications, bin} ->
          {wi_justifications, rest} =
            for _ <- wi.import_segments, reduce: {[], bin} do
              {wi_justifications, bin} ->
                <<hash::b(hash), rest::binary>> = bin
                {wi_justifications ++ [hash], rest}
            end

          {justifications ++ [wi_justifications], rest}
      end

    {extrinsics, bin} =
      for wi <- work_package.work_items, reduce: {[], bin} do
        {extrinsics, bin} ->
          {wi_extrinsics, rest} =
            for {e, size} <- wi.extrinsic,
                reduce: {[], bin} do
              {wi_extrinsics, bin} ->
                <<data::binary-size(size), rest::binary>> = bin

                if(h(data) != e,
                  do: raise("Extrinsic hash mismatch: expected #{e}, got #{h(data)}")
                )

                {wi_extrinsics ++ [data], rest}
            end

          {extrinsics ++ [wi_extrinsics], rest}
      end

    {%__MODULE__{
       work_package: work_package,
       import_segments: import_segments,
       justifications: justifications,
       extrinsics: extrinsics
     }, bin}
  end
end
