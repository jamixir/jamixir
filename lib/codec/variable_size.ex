defmodule Codec.VariableSize do
  defstruct [:value, :size]

  def new(value) do
    %__MODULE__{value: value, size: size(value)}
  end

  defp size(value) when is_list(value), do: length(value)
  defp size(value) when is_tuple(value), do: tuple_size(value)
  defp size(value) when is_binary(value), do: byte_size(value)
  # Default case
  defp size(_value), do: 0
end
