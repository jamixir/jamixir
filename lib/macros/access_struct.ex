defmodule AccessStruct do
  defmacro __using__(_opts) do
    quote do
      @behaviour Access

      @impl Access
      def fetch(container, key) do
        Map.fetch(Map.from_struct(container), key)
      end

      @impl Access
      def get_and_update(container, key, fun) do
        value = Map.get(container, key)
        {get, update} = fun.(value)
        {get, Map.put(container, key, update)}
      end

      @impl Access
      def pop(container, key) do
        value = Map.get(container, key)
        {value, Map.put(container, key, nil)}
      end
    end
  end
end
