defmodule IslandPulse.Islands do
  import Ecto.Query
  alias IslandPulse.Repo
  alias IslandPulse.Islands.{Island, UserIsland}

  @doc """
  Get or create an island by its code. Updates title/creator if they changed.
  """
  def get_or_create_island(island_code, attrs \\ %{}) do
    case Repo.get_by(Island, island_code: island_code) do
      %Island{} = island ->
        Island.changeset(island, attrs) |> Repo.update()

      nil ->
        attrs = Map.merge(%{island_code: island_code}, attrs)

        case Island.changeset(%Island{}, attrs) |> Repo.insert() do
          {:ok, island} -> {:ok, island}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Get an island by code.
  """
  def get_island_by_code(island_code) do
    Repo.get_by(Island, island_code: island_code)
  end

  @doc """
  Link a user to an island with the given role.
  Returns {:ok, user_island} or {:error, changeset}.
  """
  def link_user_to_island(user, island, role) when role in ["primary", "tracked"] do
    changeset =
      %UserIsland{user_id: user.id, island_id: island.id, role: role}
      |> UserIsland.changeset(%{})

    Repo.insert(changeset,
      conflict_target: [:user_id, :island_id],
      on_conflict: [set: [role: role]],
      prefix: "public"
    )
  end

  @doc """
  Unlink a user from an island.
  """
  def unlink_user_from_island(user, island) do
    Repo.delete_all(
      from(ui in UserIsland, where: ui.user_id == ^user.id and ui.island_id == ^island.id)
    )
  end

  @doc """
  List all primary islands for a user.
  """
  def list_primary_islands(user) do
    from(i in Island,
      join: ui in UserIsland,
      on: ui.island_id == i.id,
      where: ui.user_id == ^user.id and ui.role == "primary",
      preload: [:user_islands]
    )
    |> Repo.all()
  end

  @doc """
  List all tracked (competitor) islands for a user.
  """
  def list_tracked_islands(user) do
    from(i in Island,
      join: ui in UserIsland,
      on: ui.island_id == i.id,
      where: ui.user_id == ^user.id and ui.role == "tracked",
      preload: [:user_islands]
    )
    |> Repo.all()
  end

  @doc """
  List all islands for a user (primary + tracked).
  """
  def list_all_islands(user) do
    from(i in Island,
      join: ui in UserIsland,
      on: ui.island_id == i.id,
      where: ui.user_id == ^user.id,
      order_by: [asc: fragment("CASE ? WHEN 'primary' THEN 0 WHEN 'tracked' THEN 1 END", ui.role)],
      preload: [:user_islands]
    )
    |> Repo.all()
  end

  @doc """
  Count primary islands for a user.
  """
  def count_primary_islands(user) do
    from(ui in UserIsland,
      where: ui.user_id == ^user.id and ui.role == "primary",
      select: count(ui.id)
    )
    |> Repo.one()
  end

  @doc """
  Count tracked islands for a user.
  """
  def count_tracked_islands(user) do
    from(ui in UserIsland,
      where: ui.user_id == ^user.id and ui.role == "tracked",
      select: count(ui.id)
    )
    |> Repo.one()
  end

  @doc """
  Get all islands that have at least one tracker (for polling).
  """
  def list_tracked_island_codes do
    from(i in Island,
      join: ui in UserIsland,
      on: ui.island_id == i.id,
      distinct: i.island_code,
      select: i.island_code
    )
    |> Repo.all()
  end

  @doc """
  List all islands (for admin).
  """
  def list_all_islands do
    Repo.all(Island)
  end

  @doc """
  List user IDs tracking a given island.
  """
  def list_user_ids_for_island(island) do
    from(ui in UserIsland,
      where: ui.island_id == ^island.id,
      select: ui.user_id
    )
    |> Repo.all()
  end

  @doc """
  Check if an island's version info changed (title or creation_tool).
  Returns {:changed, changes} or {:unchanged}.
  """
  def check_version_change(island, new_attrs) do
    title_change =
      if island.title && new_attrs[:title] && island.title != new_attrs[:title] do
        [{:title, island.title, new_attrs[:title]}]
      else
        []
      end

    tool_change =
      if island.creation_tool && new_attrs[:creation_tool] &&
           island.creation_tool != new_attrs[:creation_tool] do
        [{:creation_tool, island.creation_tool, new_attrs[:creation_tool]}]
      else
        []
      end

    changes = title_change ++ tool_change

    case changes do
      [] -> {:unchanged}
      _ -> {:changed, changes}
    end
  end
end
