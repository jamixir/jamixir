defmodule StoragePrefix do
  defmacro __using__(_) do
    quote do
      @p_child "c"
      @p_block "b"
      @p_preimage "p"
      @p_wp "w"
      @p_guarantee "g"
      @p_segments_root "r"
      @p_state "s"
      @p_state_root "R"
      @p_timeslot "t"
      @p_segment "s"
      @p_segment_core "k"
      @p_ticket "T"
      @p_segment_shard "S"
    end
  end
end
