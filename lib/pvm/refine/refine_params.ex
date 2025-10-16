defmodule PVM.Refine.RefineParams do
  defstruct [
    :work_package,
    :work_item_index,
    :authorizer_trace,
    :import_segments,
    :export_segment_offset,
    :extrinsics,
    :services,
    :service_id
  ]
end
