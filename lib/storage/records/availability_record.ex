defmodule Storage.AvailabilityRecord do
  alias Block.Extrinsic.AvailabilitySpecification
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @castable_fields [
    :work_package_hash,
    :bundle_length,
    :erasure_root,
    :exports_root,
    :segment_count,
    :shard_index,
    :inserted_at,
    :updated_at
  ]
  @required_fields [
    :work_package_hash,
    :bundle_length,
    :erasure_root,
    :exports_root,
    :segment_count,
    :shard_index
  ]

  schema "availability" do
    field(:work_package_hash, :binary, primary_key: true)
    field(:shard_index, :integer)
    field(:bundle_length, :integer)
    field(:erasure_root, :binary)
    field(:exports_root, :binary)
    field(:segment_count, :integer)

    timestamps(type: :utc_datetime)
  end

  def changeset(availability, attrs) do
    availability
    |> cast(attrs, @castable_fields)
    |> validate_required(@required_fields)
    |> validate_number(:bundle_length, greater_than: 0)
    |> validate_number(:segment_count, greater_than_or_equal_to: 0)
    |> validate_number(:shard_index, greater_than_or_equal_to: 0)
  end

  def from_spec(%AvailabilitySpecification{} = spec, shard_index) do
    %__MODULE__{
      work_package_hash: spec.work_package_hash,
      bundle_length: spec.length,
      erasure_root: spec.erasure_root,
      exports_root: spec.exports_root,
      segment_count: spec.segment_count,
      shard_index: shard_index
    }
  end
end
