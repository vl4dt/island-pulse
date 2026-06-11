defmodule IslandPulse.Metrics.PollAllIslandsJob do
  @moduledoc """
  Trigger worker that enqueues a PollIslandJob for each tracked island.
  Scheduled via Oban cron every 30 minutes.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias IslandPulse.{FortniteApi, Islands}

  @impl true
  def perform(%Oban.Job{}) do
    # Check circuit breaker
    if FortniteApi.circuit_open?() do
      Logger.warning("Circuit breaker open — skipping all island polling")
      {:ok, :skipped}
    else
      island_codes = Islands.list_tracked_island_codes()

      Logger.info("Enqueueing polling jobs for #{length(island_codes)} islands")

      Enum.each(island_codes, fn code ->
        IslandPulse.Metrics.PollIslandJob.new(%{island_code: code})
        |> Oban.insert()
      end)

      {:ok, %{enqueued: length(island_codes)}}
    end
  end
end
