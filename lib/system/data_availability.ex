defmodule System.DataAvailability do
  @callback do_get_segment(binary(), non_neg_integer()) :: binary()

  def get_segment(merkle_root, segment_index) do
    module = Application.get_env(:jamixir, :data_availability, __MODULE__)

    module.do_get_segment(merkle_root, segment_index)
  end

  def do_get_segment(_merkle_root, _segment_index) do
    # TODO: Implement this function
  end
end
