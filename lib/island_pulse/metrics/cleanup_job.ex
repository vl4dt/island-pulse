defmodule IslandPulse.Metrics.CleanupJob do
  @moduledoc """
  Oban worker to clean up old metrics beyond retention period.
  Runs hourly via cron.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias IslandPulse.Metrics

  @impl true
  def perform(%Oban.Job{}) do
    retention_config = Application.get_env(:island_pulse, :retention) || %{}

    hour_days = Map.get(retention_config, :hour_days, 30)
    minute_days = Map.get(retention_config, :minute_days, 7)

    deleted_hour = Metrics.cleanup_hour_metrics(hour_days)
    deleted_minute = Metrics.cleanup_minute_metrics(minute_days)

    Logger.info(
      "Cleanup: removed #{deleted_hour} hour-level and #{deleted_minute} minute-level metrics"
    )

    {:ok, %{hour_deleted: deleted_hour, minute_deleted: deleted_minute}}
  end
end
