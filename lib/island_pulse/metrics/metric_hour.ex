defmodule IslandPulse.Metrics.MetricHour do
  use Ecto.Schema
  import Ecto.Changeset

  schema "metrics_hour" do
    field :metric_date, :naive_datetime
    field :plays, :integer
    field :unique_players, :integer
    field :minutes_played, :integer
    field :peak_ccu, :integer
    field :favorites, :integer
    field :recommendations, :integer

    belongs_to :island, IslandPulse.Islands.Island

    timestamps()
  end

  def changeset(metric, attrs) do
    metric
    |> cast(attrs, [
      :metric_date,
      :plays,
      :unique_players,
      :minutes_played,
      :peak_ccu,
      :favorites,
      :recommendations
    ])
    |> validate_required([:metric_date])
    |> unique_constraint(:island_id_metric_date_index, name: :idx_metrics_hour_island_date)
  end
end
