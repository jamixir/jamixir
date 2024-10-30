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

  # For functions with arguments
  defmacro defmockable({name, _context, args} = func) when is_atom(name) and is_list(args) do
    quote bind_quoted: [func: Macro.escape(func), name: name, args: Macro.escape(args)] do
      def unquote(name)(unquote_splicing(args)) do
        mock_module = get_mock_module()

        if mock_module != __MODULE__ and
             function_exported?(mock_module, unquote(name), length(unquote(args))) do
          apply(mock_module, unquote(name), unquote(args))
        else
          apply(__MODULE__, :"#{unquote(name)}_impl", unquote(args))
        end
      end
    end
  end

  # For functions with no arguments
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

  # For functions with arguments and do block
  defmacro defmockable({name, _context, args} = func, do: body) when is_list(args) do
    quote do
      def unquote(:"#{name}_impl")(unquote_splicing(args)), do: unquote(body)
      defmockable(unquote(func))
    end
  end

  # For atom name with do block (Constants.ex style)
  defmacro defmockable(name, do: body) when is_atom(name) do
    quote do
      def unquote(:"#{name}_impl")(), do: unquote(body)
      defmockable(unquote(name))
    end
  end
end
