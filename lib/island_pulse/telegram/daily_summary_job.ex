defmodule IslandPulse.Telegram.DailySummaryJob do
  @moduledoc """
  Oban worker to send daily summaries to all users at 6 PM UTC.
  Scheduled via cron in config/dev.exs.
  """
  use Oban.Worker, queue: :alerts, max_attempts: 2

  require Logger

  import Ecto.Query
  alias IslandPulse.Repo
  alias IslandPulse.{Accounts, Islands, Metrics}
  alias IslandPulse.Alerts.Alert

  @impl true
  def perform(%Oban.Job{}) do
    users = Accounts.list_users()

    Enum.each(users, fn user ->
      primary_islands = Islands.list_primary_islands(user)

      Enum.each(primary_islands, fn island ->
        metrics = Metrics.latest_day_metrics(island)

        if metrics && metrics.plays do
          # Count today's alerts
          today_start = NaiveDateTime.new!(Date.utc_today(), Time.new!(0, 0, 0))

          today_alerts =
            from(a in Alert,
              where:
                a.user_id == ^user.id and a.island_id == ^island.id and a.sent_at >= ^today_start,
              select: count(a.id)
            )
            |> Repo.one()

          # Get a quick tip
          tip = get_tip()

          IslandPulse.Telegram.Bot.send_daily_summary(
            user.telegram_id,
            island.title || island.island_code,
            metrics,
            today_alerts || 0,
            tip
          )
        end
      end)
    end)

    {:ok, :sent}
  end

  defp get_tip do
    tips = [
      "Try adding a clear spawn point with visual markers to help new players orient themselves.",
      "Consider adding a tutorial area for first-time visitors to increase retention.",
      "Host a community event during peak hours (evenings UTC) to boost engagement.",
      "Share your island on Fortnite.FYI and Discord servers to attract new players.",
      "Update your island's title with the current version or event name to stand out in search.",
      "Add social features like team chat or voting to encourage group play.",
      "Create a lobby with clear mode descriptions so players know what to expect."
    ]

    day = :calendar.day_of_the_week(:calendar.date_to_gregorian_days(Date.utc_today()))
    Enum.at(tips, rem(day - 1, length(tips)))
  end
end
