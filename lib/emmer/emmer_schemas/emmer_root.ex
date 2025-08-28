defmodule Emmer.EmmerRoot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emmer_roots" do
    field :name, :string
    field :home_page, :string
    field :path_to_config, :string
    field :browse_dir, :string, default: "dist"
    field :status, :string, default: "stopped"
    field :last_build_at, :utc_datetime
    field :polling, :boolean, default: false
    field :last_error, {:array, :map}
    field :button_position, :string, default: "bottom-right"

    timestamps()
  end

  @doc false
  def changeset(watcher, attrs) do
    watcher
    |> cast(attrs, [:name, :path_to_config, :status, :last_build_at, :polling, :last_error, :button_position, :home_page, :browse_dir])
    |> validate_required([:name, :path_to_config])
    |> validate_directory_exists(:path_to_config)
    |> validate_file_exists(:path_to_config)
    |> unique_constraint(:path_to_config)
  end

  defp validate_directory_exists(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if File.dir?(value) do
        []
      else
        [{field, "directory does not exist"}]
      end
    end)
  end

  defp validate_file_exists(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if File.exists?(value <> "/emmer.config.yaml") do
        []
      else
        [{field, "no emmer.config.yaml file present"}]
      end
    end)
  end
end
