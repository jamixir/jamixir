defmodule RangeMacros do
  defmacro from(left, to: right) do
    quote do
      if unquote(left) < unquote(right) do
        Enum.to_list(unquote(left)..(unquote(right) - 1))
      else
        []
      end
    end
  end

  defmacro from_0_to(n) do
    quote do
      from(0, to: unquote(n))
    end
  end
end
