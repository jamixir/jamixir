defmodule StoragePrefix do
  defmacro __using__(_) do
    quote do
      @p_child "c"
      @p_block "b"
      @p_preimage "p"
      @p_wp "w"
      @p_guarantee "g"
    end
  end
end
