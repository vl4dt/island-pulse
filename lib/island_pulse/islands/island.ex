defmodule IslandPulse.Islands.Island do
  use Ecto.Schema
  import Ecto.Changeset

  schema "islands" do
    field :island_code, :string
    field :title, :string
    field :creator_name, :string
    field :creation_tool, :string
    field :first_seen_at, :naive_datetime

    has_many :user_islands, IslandPulse.Islands.UserIsland
    has_many :metrics_day, IslandPulse.Metrics.MetricDay
    has_many :metrics_hour, IslandPulse.Metrics.MetricHour
    has_many :metrics_minute, IslandPulse.Metrics.MetricMinute

    timestamps()
  end

  def changeset(island, attrs) do
    island
    |> cast(attrs, [:island_code, :title, :creator_name, :creation_tool])
    |> validate_required([:island_code])
    |> unique_constraint(:island_code)
    |> trim_strings()
  end

  defp trim_strings(changeset) do
    update_change(changeset, :island_code, &String.trim/1)
    |> update_change(:title, &String.trim/1)
    |> update_change(:creator_name, &String.trim/1)
  end
end
