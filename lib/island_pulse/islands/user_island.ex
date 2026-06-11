defmodule IslandPulse.Islands.UserIsland do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_islands" do
    field :role, :string

    belongs_to :user, IslandPulse.Accounts.User
    belongs_to :island, IslandPulse.Islands.Island

    timestamps()
  end

  def changeset(user_island, attrs) do
    user_island
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, ["primary", "tracked"])
    |> unique_constraint(:user_id_island_id_index, name: :user_islands_user_id_island_id_index)
  end
end
