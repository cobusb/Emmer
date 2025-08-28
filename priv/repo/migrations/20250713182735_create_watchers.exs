defmodule Emmer.Repo.Migrations.CreateWatchers do
  use Ecto.Migration

  def change do
    create table(:emmer_roots) do
      add :name, :string, null: false
      add :path_to_config, :string, null: false
      add :status, :string, default: "stopped"
      add :last_build_at, :utc_datetime
      add :polling, :boolean, default: false
      add :last_error, {:array, :map}
      add :button_position, :string, default: "bottom-right"
      add :home_page, :string, default: "index.html"
      add :browse_dir, :string, default: "dist"

      timestamps()
    end

    create table(:emmer_builds, primary_key: false) do
      add :build_id, :string, primary_key: true
      add :emmer_root_id, references(:emmer_roots, on_delete: :delete_all)
      add :result, :string
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :log, {:array, :map}
    end

    create unique_index(:emmer_roots, [:path_to_config])
  end
end
