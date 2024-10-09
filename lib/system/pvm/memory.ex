defmodule System.PVM.Memory do
  # Formula (35) v0.4.1
  @type t :: %__MODULE__{
          # V
          octets: binary(),
          # A
          access: list(Types.memory_access())
        }

  defstruct octets: <<>>,
            access: []

  # Formula (36) v0.4.1
  @spec readable_indexes(t()) :: MapSet.t(integer())
  def readable_indexes(%__MODULE__{access: access}) do
    Stream.with_index(access)
    |> Enum.reduce([], fn {access, index}, acc ->
      if access != nil do
        [index | acc]
      else
        acc
      end
    end)
    |> MapSet.new()
  end

  @spec writable_indexes(t()) :: MapSet.t(integer())
  def writable_indexes(%__MODULE__{access: access}) do
    Stream.with_index(access)
    |> Enum.reduce([], fn {access, index}, acc ->
      if access == :write do
        [index | acc]
      else
        acc
      end
    end)
    |> MapSet.new()
  end
end
