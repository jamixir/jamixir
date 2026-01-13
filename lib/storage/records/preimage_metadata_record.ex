defmodule Storage.PreimageMetadataRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @castable_fields [:hash, :service_id, :length, :status, :inserted_at, :updated_at]
  @required_fields [:hash, :service_id, :length, :status]

  schema "preimage_metadata" do
    field(:hash, :binary, primary_key: true)
    field(:service_id, :integer, primary_key: true)
    field(:length, :integer)

    field(:status, Ecto.Enum,
      values: [:pending, :included],
      default: :pending
    )

    timestamps(type: :utc_datetime)
  end

  def changeset(preimage, attrs) do
    preimage
    |> cast(attrs, @castable_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:hash, :service_id], name: "preimage_metadata_hash_service_id_index")
  end
end
