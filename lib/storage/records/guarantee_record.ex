defmodule Storage.GuaranteeRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @castable_fields [
    :work_report_hash,
    :core_index,
    :timeslot,
    :credentials,
    :inserted_at,
    :updated_at,
    :status,
    :included_in_block
  ]
  @required_fields [:work_report_hash, :core_index, :timeslot, :credentials]

  schema "guarantees" do
    field(:core_index, :integer, primary_key: true)
    field(:work_report_hash, :binary)

    field(:timeslot, :integer)
    field(:credentials, :binary)

    timestamps(type: :utc_datetime)

    field(:status, Ecto.Enum,
      values: [:pending, :included, :rejected],
      default: :pending
    )

    field(:included_in_block, :binary)
  end

  def changeset(guarantee, attrs) do
    guarantee
    |> cast(attrs, @castable_fields)
    |> validate_required(@required_fields)
    |> validate_number(:core_index, greater_than_or_equal_to: 0)
  end
end
