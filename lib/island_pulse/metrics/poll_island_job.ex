defmodule IslandPulse.Metrics.PollIslandJob do
  @moduledoc """
  Oban worker to poll metrics for a single island.
  One job per island, bounded concurrency via queue config.
  """
  use Oban.Worker, queue: :polling, max_attempts: 3

  require Logger

  alias IslandPulse.{Alerts.AlertEngine, Accounts, FortniteApi, Islands, Metrics}
  alias IslandPulse.Telegram.Bot

  @impl true
  def perform(%Oban.Job{args: %{"island_code" => island_code}}) do
    # Check circuit breaker
    if FortniteApi.circuit_open?() do
      Logger.warning("Circuit breaker open — skipping poll for #{island_code}")
      {:ok, :skipped}
    else
      poll_island(island_code)
    end
  end

  defp poll_island(island_code) do
    # Fetch day-level metrics
    case FortniteApi.fetch_metrics(island_code, "day") do
      {:ok, metrics_data} ->
        parsed = FortniteApi.parse_metrics(metrics_data)

        # Get or create island
        case Islands.get_or_create_island(island_code) do
          {:ok, %Islands.Island{} = island} ->
            # Store metrics
            Enum.each(parsed, fn metric ->
              case metric.interval do
                "day" ->
                  Metrics.upsert_day_metric(
                    island,
                    Map.take(metric, [
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
                  )

                "hour" ->
                  Metrics.upsert_hour_metric(
                    island,
                    Map.take(metric, [
                      :metric_date,
                      :plays,
                      :unique_players,
                      :minutes_played,
                      :peak_ccu,
                      :favorites,
                      :recommendations
                    ])
                  )

                _ ->
                  :ok
              end
            end)

            # Evaluate alerts and deliver
            evaluate_and_deliver_alerts(island)

            {:ok, :poll_complete}

          {:error, _} ->
            {:error, :island_not_found}
        end

      {:error, :rate_limited} ->
        Logger.warning("Rate limited when polling #{island_code}")
        {:error, :rate_limited}

      {:error, reason} ->
        Logger.error("Failed to poll #{island_code}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp evaluate_and_deliver_alerts(island) do
    alerts = AlertEngine.evaluate(island)
    user_ids = Islands.list_user_ids_for_island(island)

    Enum.each(alerts, fn alert_map ->
      # Save to DB for each tracking user
      Enum.each(user_ids, fn user_id ->
        case Accounts.get_user_by_id(user_id) do
          %Accounts.User{} = user ->
            AlertEngine.save_alert(user, alert_map)

            # Send CRITICAL alerts immediately
            if alert_map.severity == "critical" do
              value_str =
                case alert_map.value do
                  %Decimal{} = d -> Decimal.to_string(d)
                  nil -> "N/A"
                  other -> to_string(other)
                end

              pct_change =
                case alert_map.threshold_pct do
                  %Decimal{} = d -> Decimal.to_float(d)
                  nil -> 0
                end

              Bot.send_critical_alert(
                user.telegram_id,
                island.title || island.island_code,
                alert_map.metric_name,
                value_str,
                alert_map.direction,
                pct_change
              )
            end

          nil ->
            :ok
        end
      end)
    end)
  end
end
