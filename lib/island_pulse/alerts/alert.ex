defmodule IslandPulse.Alerts.Alert do
  use Ecto.Schema
  import Ecto.Changeset

  schema "alerts" do
    field :severity, :string
    field :metric_name, :string
    field :value, :decimal
    field :threshold_pct, :decimal
    field :direction, :string
    field :sent_at, :naive_datetime
    field :cooldown_until, :naive_datetime

    belongs_to :user, IslandPulse.Accounts.User
    belongs_to :island, IslandPulse.Islands.Island

    timestamps()
  end

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:severity, :metric_name, :value, :threshold_pct, :direction])
    |> validate_required([:severity, :metric_name])
    |> validate_inclusion(:severity, ["critical", "warning", "info"])
  end
end
