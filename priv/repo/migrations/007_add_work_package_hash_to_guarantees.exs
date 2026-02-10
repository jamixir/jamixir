defmodule Jamixir.Repo.Migrations.AddWorkPackageHashToGuarantees do
  use Ecto.Migration

  def change do
    alter table(:guarantees) do
      add :work_package_hash, :blob
    end

    create index(:guarantees, [:work_package_hash])
  end
end
