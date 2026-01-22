defmodule Jamixir.Repo.Migrations.CreateBlocks do
  use Ecto.Migration

  def change do
    create table(:blocks, primary_key: false) do
      add :header_hash, :binary, null: false, primary_key: true
      add :parent_header_hash, :binary, null: false
      add :slot, :integer, null: false
      add :applied, :boolean, null: false, default: false
    end

    create index(:blocks, [:parent_header_hash])
    create index(:blocks, [:slot])
    create index(:blocks, [:parent_header_hash, :slot])
  end
end
