defmodule OriginalModules do
  defmacro with_jamixir_env(key, value, do: block) do
    quote do
      original_value = Application.get_env(:jamixir, unquote(key))

      try do
        Application.put_env(:jamixir, unquote(key), unquote(value))
        unquote(block)
      after
        Application.put_env(:jamixir, unquote(key), original_value)
      end
    end
  end

  defmacro with_original_modules(modules, do: block) do
    quote do
      with_jamixir_env(:original_modules, unquote(modules)) do
        unquote(block)
      end
    end
  end
end
