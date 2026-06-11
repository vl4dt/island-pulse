defmodule IslandPulse.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :telegram_id, :integer
    field :tier, :string, default: "free"

    has_many :user_islands, IslandPulse.Islands.UserIsland
    has_many :alerts, IslandPulse.Alerts.Alert

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:telegram_id, :tier])
    |> validate_required([:telegram_id])
    |> unique_constraint(:telegram_id)
    |> validate_inclusion(:tier, ["free", "creator", "pro"])
  end

  def tier_changeset(user, tier) do
    user
    |> change(tier: tier)
    |> validate_inclusion(:tier, ["free", "creator", "pro"])
  end
end
