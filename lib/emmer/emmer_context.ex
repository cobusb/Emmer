defmodule Emmer.EmmerContext do
  @moduledoc """
  Context module for EmmerRoot operations with automatic change broadcasting.
  """

  import Ecto.Query
  require Logger
  alias Emmer.Repo
  alias Emmer.EmmerRoot

  @doc """
  Gets all EmmerRoot records.
  """
  def list_emmer_roots do
    Repo.all(EmmerRoot)
  end

  @doc """
  Gets a single EmmerRoot by ID.
  """
  def get_emmer_root!(id), do: Repo.get!(EmmerRoot, id)

  @doc """
  Gets a single EmmerRoot by ID, returns nil if not found.
  """
  def get_emmer_root(id), do: Repo.get(EmmerRoot, id)

  @doc """
  Creates a new EmmerRoot and broadcasts the change.
  """
  def create_emmer_root(attrs \\ %{}) do
    case %EmmerRoot{}
         |> EmmerRoot.changeset(attrs)
         |> Repo.insert() do
      {:ok, emmer_root} ->
        broadcast_created(emmer_root)
        {:ok, emmer_root}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates an EmmerRoot with a changeset and broadcasts the change.
  """
  def update_emmer_root(%EmmerRoot{} = emmer_root, changeset) do
    case Repo.update(changeset) do
      {:ok, updated_emmer_root} ->
        broadcast_updated(updated_emmer_root)
        {:ok, updated_emmer_root}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes an EmmerRoot and broadcasts the change.
  """
  def delete_emmer_root(%EmmerRoot{} = emmer_root) do
    case Repo.delete(emmer_root) do
      {:ok, deleted_emmer_root} ->
        broadcast_deleted(deleted_emmer_root.id)
        {:ok, deleted_emmer_root}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking EmmerRoot changes.
  """
  def change_emmer_root(%EmmerRoot{} = emmer_root, attrs \\ %{}) do
    EmmerRoot.changeset(emmer_root, attrs)
  end

  @doc """
  Creates a new EmmerRoot changeset.
  """
  def new_emmer_root_changeset do
    EmmerRoot.changeset(%EmmerRoot{}, %{})
  end

  # PubSub Topic
  @topic "emmer_roots"

  # PubSub Broadcasting Functions

  @doc """
  Broadcasts when an EmmerRoot record is created.
  """
  def broadcast_created(emmer_root) do
    Logger.debug("EmmerRootContext: Broadcasting created event for #{emmer_root.id}")
    Phoenix.PubSub.broadcast(Emmer.PubSub, @topic, {:emmer_root_created, emmer_root})
  end

  @doc """
  Broadcasts when an EmmerRoot record is updated.
  """
  def broadcast_updated(emmer_root) do
    Logger.debug("EmmerRootContext: Broadcasting updated event for #{emmer_root.id}")
    Phoenix.PubSub.broadcast(Emmer.PubSub, @topic, {:emmer_root_updated, emmer_root})
  end

  @doc """
  Broadcasts when an EmmerRoot record is deleted.
  """
  def broadcast_deleted(emmer_root_id) do
    Logger.debug("EmmerRootContext: Broadcasting deleted event for #{emmer_root_id}")
    Phoenix.PubSub.broadcast(Emmer.PubSub, @topic, {:emmer_root_deleted, emmer_root_id})
  end

  @doc """
  Broadcasts when all EmmerRoot records should be refreshed.
  """
  def broadcast_refresh_all do
    Logger.debug("EmmerRootContext: Broadcasting refresh_all event")
    Phoenix.PubSub.broadcast(Emmer.PubSub, @topic, :emmer_roots_refresh_all)
  end

  @doc """
  Gets the topic name for EmmerRoot events.
  """
  def topic, do: @topic
end
