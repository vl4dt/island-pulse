defmodule IslandPulse.IslandsTest do
  use IslandPulse.DataCase, async: true

  alias IslandPulse.Islands
  alias IslandPulse.Accounts.User

  describe "get_or_create_island/2" do
    test "creates a new island" do
      {:ok, island} = Islands.get_or_create_island("NEW123", %{title: "New Island"})

      assert island.island_code == "NEW123"
      assert island.title == "New Island"
    end

    test "returns existing island and updates fields" do
      {:ok, original} = Islands.get_or_create_island("EXISTS1", %{title: "Original"})
      {:ok, updated} = Islands.get_or_create_island("EXISTS1", %{title: "Updated"})

      assert updated.id == original.id
      assert updated.title == "Updated"
    end

    test "trims whitespace from island_code" do
      {:ok, island} = Islands.get_or_create_island("  TRIM456  ", %{title: "Trimmed"})

      assert island.island_code == "TRIM456"
    end

    test "returns error when island_code is missing" do
      {:error, changeset} = Islands.get_or_create_island("", %{title: "No Code"})

      assert changeset.errors[:island_code]
    end
  end

  describe "get_island_by_code/1" do
    test "returns island when it exists" do
      {:ok, island} = Islands.get_or_create_island("BYCODE1", %{title: "By Code"})

      found = Islands.get_island_by_code("BYCODE1")
      assert found.id == island.id
    end

    test "returns nil when island does not exist" do
      assert Islands.get_island_by_code("NONEXISTENT") == nil
    end
  end

  describe "link_user_to_island/3" do
    setup [:create_user_and_island]

    test "links user as primary", %{user: user, island: island} do
      assert {:ok, _} = Islands.link_user_to_island(user, island, "primary")
      assert Islands.count_primary_islands(user) == 1
    end

    test "links user as tracked", %{user: user, island: island} do
      assert {:ok, _} = Islands.link_user_to_island(user, island, "tracked")
      assert Islands.count_tracked_islands(user) == 1
    end

    test "updates role on conflict (upsert)", %{user: user, island: island} do
      Islands.link_user_to_island(user, island, "primary")
      Islands.link_user_to_island(user, island, "tracked")

      # Role should be updated to tracked
      assert Islands.count_primary_islands(user) == 0
      assert Islands.count_tracked_islands(user) == 1
    end

    test "returns error for invalid role" do
      user = insert_user()
      {:ok, island} = Islands.get_or_create_island("ROLE_TEST", %{title: "Role Test"})

      # Invalid role should raise a FunctionClauseError (guard clause rejects it)
      assert_raise(FunctionClauseError, fn ->
        Islands.link_user_to_island(user, island, "invalid_role")
      end)
    end
  end

  describe "unlink_user_from_island/2" do
    setup [:create_user_and_island]

    test "removes the link", %{user: user, island: island} do
      Islands.link_user_to_island(user, island, "primary")
      assert Islands.count_primary_islands(user) == 1

      Islands.unlink_user_from_island(user, island)
      assert Islands.count_primary_islands(user) == 0
    end
  end

  describe "list_primary_islands/1" do
    setup [:create_user_and_island]

    test "returns only primary islands", %{user: user, island: island} do
      Islands.link_user_to_island(user, island, "primary")

      # Add another island as tracked
      {:ok, other} = Islands.get_or_create_island("OTHER1", %{title: "Other"})
      Islands.link_user_to_island(user, other, "tracked")

      primaries = Islands.list_primary_islands(user)
      assert length(primaries) == 1
      assert Enum.at(primaries, 0).id == island.id
    end

    test "returns empty list when no primary islands", %{user: user} do
      assert Islands.list_primary_islands(user) == []
    end
  end

  describe "list_tracked_islands/1" do
    setup [:create_user_and_island]

    test "returns only tracked islands", %{user: user, island: island} do
      Islands.link_user_to_island(user, island, "tracked")

      # Add another as primary
      {:ok, other} = Islands.get_or_create_island("OTHER2", %{title: "Other"})
      Islands.link_user_to_island(user, other, "primary")

      tracked = Islands.list_tracked_islands(user)
      assert length(tracked) == 1
      assert Enum.at(tracked, 0).id == island.id
    end
  end

  describe "list_all_islands/1" do
    setup [:create_user_and_island]

    test "returns both primary and tracked islands", %{user: user, island: island} do
      Islands.link_user_to_island(user, island, "primary")

      {:ok, other} = Islands.get_or_create_island("OTHER3", %{title: "Other"})
      Islands.link_user_to_island(user, other, "tracked")

      all = Islands.list_all_islands(user)
      assert length(all) == 2
      # Primary should come first due to ordering
      assert Enum.at(all, 0).id == island.id
    end
  end

  describe "list_tracked_island_codes/0" do
    test "returns unique island codes for tracked islands" do
      user1 = insert_user()
      user2 = insert_user()
      {:ok, island} = Islands.get_or_create_island("SHARED1", %{title: "Shared"})

      Islands.link_user_to_island(user1, island, "primary")
      Islands.link_user_to_island(user2, island, "tracked")

      codes = Islands.list_tracked_island_codes()
      assert "SHARED1" in codes
      # Should be unique even if multiple users track it
      assert length(codes) == 1
    end
  end

  describe "list_user_ids_for_island/1" do
    setup [:create_user_and_island]

    test "returns user IDs tracking an island", %{user: user, island: island} do
      Islands.link_user_to_island(user, island, "primary")

      user2 = insert_user()
      Islands.link_user_to_island(user2, island, "tracked")

      ids = Islands.list_user_ids_for_island(island)
      assert length(ids) == 2
      assert user.id in ids
      assert user2.id in ids
    end

    test "returns empty list when no users track the island", %{island: island} do
      assert Islands.list_user_ids_for_island(island) == []
    end
  end

  describe "check_version_change/2" do
    setup [:create_user_and_island]

    test "detects title change", %{island: island} do
      original_title = island.title
      result = Islands.check_version_change(island, %{title: "New Title"})
      assert {:changed, changes} = result

      assert Enum.any?(changes, fn {:title, old, new} ->
               old == original_title and new == "New Title"
             end)
    end

    test "detects creation_tool change", %{island: island} do
      original_tool = "Original Tool"
      # First set the tool
      {:ok, updated} =
        Islands.get_or_create_island(island.island_code, %{creation_tool: original_tool})

      result = Islands.check_version_change(updated, %{creation_tool: "New Tool"})
      assert {:changed, changes} = result

      assert Enum.any?(changes, fn {:creation_tool, old, new} ->
               old == original_tool and new == "New Tool"
             end)
    end

    test "returns unchanged when nothing changed", %{island: island} do
      result = Islands.check_version_change(island, %{})
      assert {:unchanged} = result
    end

    test "detects both title and tool changes" do
      _user = insert_user()

      {:ok, island} =
        Islands.get_or_create_island("VCHANGE", %{title: "Old Title", creation_tool: "Old Tool"})

      result =
        Islands.check_version_change(island, %{title: "New Title", creation_tool: "New Tool"})

      assert {:changed, changes} = result
      assert length(changes) == 2
    end
  end

  # --- Fixtures ---

  defp create_user_and_island(_) do
    user = insert_user()

    {:ok, island} =
      Islands.get_or_create_island("TEST_#{System.unique_integer([:positive])}", %{
        title: "Test Island"
      })

    {:ok, user: user, island: island}
  end

  defp insert_user do
    %User{}
    |> User.changeset(%{telegram_id: System.unique_integer([:positive]), tier: "free"})
    |> Repo.insert!()
  end
end
