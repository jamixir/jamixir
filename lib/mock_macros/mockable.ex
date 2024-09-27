defmodule Mockable do
  defmacro __using__(_opts) do
    quote do
      import Mockable, only: [defmockable: 1, defmockable: 2]
      @before_compile Mockable
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def get_mock_module do
        Application.get_env(:jamixir, __MODULE__, __MODULE__)
      end

      defoverridable get_mock_module: 0
    end
  end

  defmacro defmockable(name) when is_atom(name) do
    quote bind_quoted: [name: name] do
      def unquote(name)() do
        mock_module = get_mock_module()

        if mock_module != __MODULE__ and function_exported?(mock_module, unquote(name), 0) do
          apply(mock_module, unquote(name), [])
        else
          apply(__MODULE__, :"#{unquote(name)}_impl", [])
        end
      end
    end
  end

  defmacro defmockable(name, do: body) do
    quote do
      def unquote(:"#{name}_impl")(), do: unquote(body)
      defmockable(unquote(name))
    end
  end
end
