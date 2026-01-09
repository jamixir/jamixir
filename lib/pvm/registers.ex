defmodule PVM.Registers do
  @default_tuple {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

  defstruct r: @default_tuple

  @type register :: 0..12
  @type t :: %__MODULE__{}

  @spec new() :: t()
  def new(), do: %__MODULE__{r: @default_tuple}

  @spec new(map()) :: t()
  def new(updates) when is_map(updates) do
    %__MODULE__{
      r: {
        Map.get(updates, 0, 0),
        Map.get(updates, 1, 0),
        Map.get(updates, 2, 0),
        Map.get(updates, 3, 0),
        Map.get(updates, 4, 0),
        Map.get(updates, 5, 0),
        Map.get(updates, 6, 0),
        Map.get(updates, 7, 0),
        Map.get(updates, 8, 0),
        Map.get(updates, 9, 0),
        Map.get(updates, 10, 0),
        Map.get(updates, 11, 0),
        Map.get(updates, 12, 0)
      }
    }
  end

  @spec from_list([integer()]) :: t()
  def from_list(values) when is_list(values) and length(values) == 13 do
    tuple = List.to_tuple(values)
    %__MODULE__{r: tuple}
  end

  @spec get(t(), [integer()]) :: [integer()]
  def get(%__MODULE__{r: tuple}, registers)
      when is_list(registers) and is_integer(hd(registers)) do
    for index <- registers, do: elem(tuple, index)
  end

  # Fast multi-register getters
  @spec get_2(t(), integer(), integer()) :: {integer(), integer()}
  def get_2(%__MODULE__{r: tuple}, i1, i2) do
    {elem(tuple, i1), elem(tuple, i2)}
  end

  @spec get_3(t(), integer(), integer(), integer()) :: {integer(), integer(), integer()}
  def get_3(%__MODULE__{r: tuple}, i1, i2, i3) do
    {elem(tuple, i1), elem(tuple, i2), elem(tuple, i3)}
  end

  @spec get_4(t(), integer(), integer(), integer(), integer()) ::
          {integer(), integer(), integer(), integer()}
  def get_4(%__MODULE__{r: tuple}, i1, i2, i3, i4) do
    {elem(tuple, i1), elem(tuple, i2), elem(tuple, i3), elem(tuple, i4)}
  end

  @spec get_5(t(), integer(), integer(), integer(), integer(), integer()) ::
          {integer(), integer(), integer(), integer(), integer()}
  def get_5(%__MODULE__{r: tuple}, i1, i2, i3, i4, i5) do
    {elem(tuple, i1), elem(tuple, i2), elem(tuple, i3), elem(tuple, i4), elem(tuple, i5)}
  end

  @spec to_list(t()) :: [integer()]
  def to_list(%__MODULE__{r: tuple}), do: Tuple.to_list(tuple)

  @behaviour Access

  @impl Access
  def fetch(%__MODULE__{r: tuple}, key) when is_integer(key) and key in 0..12 do
    {:ok, elem(tuple, key)}
  end

  def fetch(%__MODULE__{}, _key), do: :error
end

defimpl Inspect, for: PVM.Registers do
  def inspect(%PVM.Registers{r: tuple}, _opts) do
    register_str =
      0..12
      |> Enum.map(&"#{&1}:#{elem(tuple, &1)}")
      |> Enum.join(" ")

    "[#{register_str}]"
  end
end
