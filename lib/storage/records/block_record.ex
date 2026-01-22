defmodule Storage.BlockRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @castable_fields [:header_hash, :parent_header_hash, :slot, :applied]
  @required_fields [:header_hash, :parent_header_hash, :slot]

  schema "blocks" do
    field(:header_hash, :binary, primary_key: true)
    field(:parent_header_hash, :binary)
    field(:slot, :integer)
    field(:applied, :boolean, default: false)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, @castable_fields)
    |> validate_required(@required_fields)
    |> validate_number(:slot, greater_than_or_equal_to: 0)
    |> unique_constraint(:header_hash, name: :blocks_header_hash_index)
  end
end
