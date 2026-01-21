defmodule Storage.BlockRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @castable_fields [:header_hash, :parent_header_hash, :slot]
  @required_fields [:header_hash, :parent_header_hash, :slot]

  schema "blocks" do
    field(:header_hash, :binary, primary_key: true)
    field(:parent_header_hash, :binary)
    field(:slot, :integer)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, @castable_fields)
    |> validate_required(@required_fields)
    |> validate_number(:slot, greater_than_or_equal_to: 0)
  end
end
