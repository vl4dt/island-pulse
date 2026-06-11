defmodule IslandPulse.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    # Users
    create table(:users) do
      add :telegram_id, :bigint, null: false
      add :tier, :string, default: "free", null: false
      timestamps()
    end

    create unique_index(:users, [:telegram_id])

    # Islands (single source of truth per island_code)
    create table(:islands) do
      add :island_code, :string, size: 50, null: false
      add :title, :text
      add :creator_name, :text
      add :creation_tool, :string, size: 20
      add :first_seen_at, :naive_datetime, default: fragment("now()")
      timestamps()
    end

    create unique_index(:islands, [:island_code])

    # User-island junction with role
    create table(:user_islands) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :island_id, references(:islands, on_delete: :delete_all), null: false
      add :role, :string, size: 20, null: false
      timestamps()
    end

    create unique_index(:user_islands, [:user_id, :island_id])
    create index(:user_islands, [:island_id])

    # Metrics - day level (kept forever)
    create table(:metrics_day) do
      add :island_id, references(:islands, on_delete: :delete_all), null: false
      add :metric_date, :date, null: false
      add :plays, :integer
      add :unique_players, :integer
      add :minutes_played, :bigint
      add :peak_ccu, :integer
      add :favorites, :integer
      add :recommendations, :integer
      add :retention_d1, :decimal, precision: 5, scale: 2
      add :retention_d7, :decimal, precision: 5, scale: 2
      timestamps()
    end

    create unique_index(:metrics_day, [:island_id, :metric_date],
             name: :idx_metrics_day_island_date
           )

    create index(:metrics_day, [:island_id, {:desc, :metric_date}], name: :idx_metrics_day_latest)

    # Metrics - hour level (30 days retention)
    create table(:metrics_hour) do
      add :island_id, references(:islands, on_delete: :delete_all), null: false
      add :metric_date, :naive_datetime, null: false
      add :plays, :integer
      add :unique_players, :integer
      add :minutes_played, :bigint
      add :peak_ccu, :integer
      add :favorites, :integer
      add :recommendations, :integer
      timestamps()
    end

    create unique_index(:metrics_hour, [:island_id, :metric_date],
             name: :idx_metrics_hour_island_date
           )

    create index(:metrics_hour, [:island_id, {:desc, :metric_date}],
             name: :idx_metrics_hour_latest
           )

    # Metrics - minute level (7 days retention)
    create table(:metrics_minute) do
      add :island_id, references(:islands, on_delete: :delete_all), null: false
      add :metric_date, :naive_datetime, null: false
      add :plays, :integer
      add :unique_players, :integer
      add :minutes_played, :bigint
      add :peak_ccu, :integer
      add :favorites, :integer
      add :recommendations, :integer
      timestamps()
    end

    create unique_index(:metrics_minute, [:island_id, :metric_date],
             name: :idx_metrics_minute_island_date
           )

    create index(:metrics_minute, [:island_id, {:desc, :metric_date}],
             name: :idx_metrics_minute_latest
           )

    # Alerts
    create table(:alerts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :island_id, references(:islands, on_delete: :delete_all), null: false
      add :severity, :string, size: 20, null: false
      add :metric_name, :string, size: 50, null: false
      add :value, :decimal
      add :threshold_pct, :decimal
      add :direction, :string, size: 10
      add :sent_at, :naive_datetime, default: fragment("now()")
      add :cooldown_until, :naive_datetime
      timestamps()
    end

    create index(:alerts, [:user_id, :island_id])
    create index(:alerts, [{:desc, :sent_at}], name: :idx_alerts_sent_at_desc)

    # Oban jobs table
    execute """
            CREATE EXTENSION IF NOT EXISTS pgcrypto;
            """,
            """
            DROP EXTENSION IF EXISTS pgcrypto;
            """

    Oban.Migrations.up(version: 12)
  end
end
