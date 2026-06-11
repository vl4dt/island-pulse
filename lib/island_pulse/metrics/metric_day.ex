defmodule IslandPulse.Metrics.MetricDay do
  use Ecto.Schema
  import Ecto.Changeset

  schema "metrics_day" do
    field :metric_date, :date
    field :plays, :integer
    field :unique_players, :integer
    field :minutes_played, :integer
    field :peak_ccu, :integer
    field :favorites, :integer
    field :recommendations, :integer
    field :retention_d1, :decimal
    field :retention_d7, :decimal

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
      :recommendations,
      :retention_d1,
      :retention_d7
    ])
    |> validate_required([:metric_date])
    |> unique_constraint(:island_id_metric_date_index, name: :idx_metrics_day_island_date)
  end
end
