defmodule Storage.AssuranceRecord do
  @moduledoc """
  Ecto schema for storing Assurance extrinsics in SQLite database.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Block.Extrinsic.Assurance

  @primary_key false
  @field_names Assurance.__struct__()
               |> Map.keys()
               |> Enum.reject(&(&1 == :__struct__))

  schema "assurances" do
    field(:hash, :binary, primary_key: true)
    field(:validator_index, :integer, primary_key: true)
    field(:bitfield, :binary)
    field(:signature, :binary)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(assurance, attrs) do
    assurance
    |> cast(attrs, @field_names)
    |> validate_required(@field_names)
    |> validate_number(:validator_index, greater_than_or_equal_to: 0)
  end

  def to_assurance(%__MODULE__{} = record) do
    struct(Assurance, Map.from_struct(record))
  end
end
