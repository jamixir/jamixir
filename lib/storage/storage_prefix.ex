defmodule StoragePrefix do
  defmacro __using__(_) do
    quote do
      @p_child "c"
      @p_block "b"
      @p_preimage "p"
      @p_wp "w"
    end
  end
end
