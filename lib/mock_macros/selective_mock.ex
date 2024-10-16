defmodule SelectiveMock do
  defmacro __using__(_opts) do
    quote do
      import SelectiveMock
      Module.register_attribute(__MODULE__, :mockable, accumulate: true)
    end
  end

  defmacro mockable({name, _, args} = func, do: block) do
    quote do
      @mockable {unquote(name), unquote(Macro.escape(args)), unquote(Macro.escape(block))}
      def unquote(func) do
        # List of functions/modules to NOT mock
        mock_exclusion_list = Application.get_env(:jamixir, :original_modules, nil)

        cond do
          # If the exclusion list is nil, nothing is mocked
          mock_exclusion_list == nil ->
            unquote(block)

          # If the function or module is on the list, use the original function
          unquote(name) in mock_exclusion_list or __MODULE__ in mock_exclusion_list ->
            unquote(block)

          # Otherwise, mock the function
          true ->
            mock(unquote(name), binding())
        end
      end
    end
  end
end
