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
        # Fetch the list of functions/modules to NOT mock from :original_modules, default to nil
        mock_exclusion_list = Application.get_env(:jamixir, :original_modules, nil)

        # If the list is nil, nothing gets mocked
        if mock_exclusion_list == nil or
             (is_list(mock_exclusion_list) and Enum.member?(mock_exclusion_list, unquote(name))) or
             Enum.member?(mock_exclusion_list, __MODULE__) do
          # If the function/module is on the list or no list exists, use the original function
          unquote(block)
        else
          # Otherwise, use the mock implementation
          context = binding()
          mock(unquote(name), context)
        end
      end
    end
  end
end
