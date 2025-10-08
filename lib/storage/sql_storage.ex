defmodule Jamixir.SqlStorage do
  @moduledoc """
  SQL-based storage for block extrinsics that require querying capabilities.
  """

  alias Jamixir.Repo
  alias Storage.AssuranceRecord
  alias Block.Extrinsic.Assurance

  def save(%Assurance{} = assurance) do
    attrs =
      Map.from_struct(assurance)
      |> Map.merge(%{
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })

    %AssuranceRecord{}
    |> AssuranceRecord.changeset(attrs)
    |> Repo.insert()
  end

  def clean(Assurance), do: Repo.delete_all(AssuranceRecord)

  def get_all(Assurance) do
    Repo.all(AssuranceRecord) |> Enum.map(&AssuranceRecord.to_assurance/1)
  end
end
