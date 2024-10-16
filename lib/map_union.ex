defmodule MapUnion do
  defmacro __using__(_opts) do
    quote do
      import Kernel, except: [++: 2]
      import unquote(__MODULE__)
    end
  end

  defmacro left ++ right do
    quote do
      case {unquote(left), unquote(right)} do
        {%MapSet{} = left, %MapSet{} = right} ->
          MapSet.union(left, right)

        {%{} = left, %{} = right} ->
          Map.merge(left, right)

        {left, right} when is_list(left) and is_list(right) ->
          Kernel.++(left, right)

        _ ->
          raise ArgumentError, "Unsupported types for ++ operator"
      end
    end
  end

  defmacro left \\ right do
    quote do
      case {unquote(left), unquote(right)} do
        {%MapSet{} = left, %MapSet{} = right} ->
          MapSet.difference(left, right)

        {%{} = left, %{} = right} ->
          Map.drop(left, Map.keys(right))

        _ ->
          raise ArgumentError, "Unsupported types for - operator"
      end
    end
  end
end
