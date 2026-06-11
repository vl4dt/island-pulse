defmodule IslandPulse.Telegram.Bot do
  @moduledoc """
  Telegram bot handler for Island Pulse.
  Processes commands and sends messages via the Telegram Bot API.
  """

  require Logger

  alias IslandPulse.{Accounts, Islands, Metrics}
  alias IslandPulse.Metrics.PollIslandJob

  # --- Command Handlers ---

  @doc """
  Route an incoming Telegram message to the appropriate handler.
  """
  def handle_message(%{"message" => %{"text" => "/start", "from" => user}}) do
    {:ok, _db_user} = Accounts.get_or_create_user(user["id"])

    text = """
    🎮 Welcome to Island Pulse!

    I'll help you track your Fortnite island's health and alert you when things change.

    Get started by adding your island:
    /add <island_code>

    Or see all commands:
    /help
    """

    send_text(user["id"], text)
  end

  def handle_message(%{"message" => %{"text" => "/help", "from" => user}}) do
    text = """
    📋 Available Commands:

    /start — Start the bot
    /add <code> — Track an island (your own)
    /track <code> — Track a competitor island
    /remove <code> — Stop tracking an island
    /list — Show your tracked islands
    /status <code> — Get current metrics for an island
    /help — Show this help message

    💡 Tip: You can track up to 1 island + 1 competitor on the free tier.
    """

    send_text(user["id"], text)
  end

  def handle_message(%{"message" => %{"text" => text, "from" => user}}) when is_binary(text) do
    [command | rest] = String.split(text, " ", parts: 2)
    args = if rest != [], do: hd(rest), else: ""

    case command do
      "/add" -> handle_add(user["id"], args)
      "/track" -> handle_track(user["id"], args)
      "/remove" -> handle_remove(user["id"], args)
      "/list" -> handle_list(user["id"])
      "/status" -> handle_status(user["id"], args)
      _ -> :ok
    end
  end

  def handle_message(_), do: :ok

  # --- Command Implementations ---

  defp handle_add(user_id, island_code) do
    island_code = String.trim(island_code)

    if island_code == "" do
      send_text(user_id, "📝 Please provide an island code: /add <code>")
    else
      case Accounts.get_or_create_user(user_id) do
        {:ok, db_user} ->
          current_count = Islands.count_primary_islands(db_user)

          if current_count >= 1 and db_user.tier == "free" do
            send_text(user_id, """
            🚫 Free tier limit reached (1 island).
            Upgrade to Creator tier for up to 3 islands.
            """)
          else
            case Islands.get_or_create_island(island_code) do
              {:ok, %Islands.Island{} = island} ->
                Islands.link_user_to_island(db_user, island, "primary")

                PollIslandJob.new(%{island_code: island_code}) |> Oban.insert()

                send_text(user_id, """
                ✅ Added #{island.title || island_code} as your tracked island!

                I'll start polling its metrics every 30 minutes.
                You'll get a daily summary at 6 PM UTC.
                """)

              {:error, _} ->
                send_text(user_id, "❌ Failed to add island. Check the code and try again.")
            end
          end

        {:error, _} ->
          send_text(user_id, "❌ Something went wrong. Please try again.")
      end
    end
  end

  defp handle_track(user_id, island_code) do
    island_code = String.trim(island_code)

    if island_code == "" do
      send_text(user_id, "📝 Please provide an island code: /track <code>")
    else
      case Accounts.get_or_create_user(user_id) do
        {:ok, db_user} ->
          current_count = Islands.count_tracked_islands(db_user)

          if current_count >= 1 and db_user.tier == "free" do
            send_text(user_id, """
            🚫 Free tier limit reached (1 competitor).
            Upgrade to Creator tier for up to 3 competitors.
            """)
          else
            case Islands.get_or_create_island(island_code) do
              {:ok, %Islands.Island{} = island} ->
                Islands.link_user_to_island(db_user, island, "tracked")

                PollIslandJob.new(%{island_code: island_code}) |> Oban.insert()

                send_text(user_id, """
                ✅ Added #{island.title || island_code} as a competitor to track!

                You can compare it against your own islands.
                """)

              {:error, _} ->
                send_text(user_id, "❌ Failed to add island. Check the code and try again.")
            end
          end

        {:error, _} ->
          send_text(user_id, "❌ Something went wrong. Please try again.")
      end
    end
  end

  defp handle_remove(user_id, island_code) do
    island_code = String.trim(island_code)

    case Accounts.get_user_by_telegram_id(user_id) do
      %Accounts.User{} = db_user ->
        case Islands.get_island_by_code(island_code) do
          %Islands.Island{} = island ->
            Islands.unlink_user_from_island(db_user, island)

            send_text(
              user_id,
              "✅ Removed #{island.title || island_code} from your tracked islands."
            )

          nil ->
            send_text(user_id, "❌ Island not found in your list.")
        end

      nil ->
        send_text(user_id, "❌ Something went wrong. Please try again.")
    end
  end

  defp handle_list(user_id) do
    case Accounts.get_user_by_telegram_id(user_id) do
      %Accounts.User{} = db_user ->
        primary = Islands.list_primary_islands(db_user)
        tracked = Islands.list_tracked_islands(db_user)

        text = build_list_message(primary, tracked)
        send_text(user_id, text)

      nil ->
        send_text(user_id, "❌ Something went wrong. Please try again.")
    end
  end

  defp handle_status(user_id, island_code) do
    island_code = String.trim(island_code)

    case Islands.get_island_by_code(island_code) do
      %Islands.Island{} = island ->
        metrics = Metrics.latest_day_metrics(island)
        text = build_status_message(island, metrics)
        send_text(user_id, text)

      nil ->
        send_text(user_id, "❌ Island not found.")
    end
  end

  # --- Message Builders ---

  defp build_list_message(primary, tracked) do
    lines = ["📋 Your Tracked Islands:"]

    primary_lines =
      Enum.map(primary, fn island ->
        metrics = Metrics.latest_day_metrics(island)
        plays = if metrics && metrics.plays, do: to_string(metrics.plays), else: "—"

        "  🏝️ #{island.title || island.island_code} (#{island.island_code})\n     Plays: #{plays}"
      end)

    (lines ++
       primary_lines ++
       if tracked != [] do
         ["", "👀 Competitors:"] ++
           Enum.map(tracked, fn island ->
             metrics = Metrics.latest_day_metrics(island)
             plays = if metrics && metrics.plays, do: to_string(metrics.plays), else: "—"

             "  🏝️ #{island.title || island.island_code} (#{island.island_code})\n     Plays: #{plays}"
           end)
       else
         []
       end)
    |> Enum.join("\n")
  end

  defp build_status_message(island, nil) do
    """
    📊 #{island.title || island.island_code}

    No data available yet. The island may not have enough players (min 5 unique players required).
    """
  end

  defp build_status_message(island, metrics) do
    """
    📊 #{island.title || island.island_code}

    🎮 Plays: #{format_number(metrics.plays)}
    👥 Unique Players: #{format_number(metrics.unique_players)}
    ⏱️ Minutes Played: #{format_number(metrics.minutes_played)}
    📈 Peak CCU: #{format_number(metrics.peak_ccu)}
    ❤️ Favorites: #{format_number(metrics.favorites)}
    🔖 Recommendations: #{format_number(metrics.recommendations)}

    """ <>
      if metrics.retention_d1 do
        "📅 D1 Retention: #{Decimal.to_float(metrics.retention_d1)}%\n"
      else
        ""
      end <>
      if metrics.retention_d7 do
        "📅 D7 Retention: #{Decimal.to_float(metrics.retention_d7)}%\n"
      else
        ""
      end
  end

  defp format_number(nil), do: "—"
  defp format_number(n) when is_integer(n), do: :io_lib.format("~,B", [n]) |> to_string()

  # --- Sending Messages ---

  @doc """
  Send a text message to a Telegram user.
  """
  def send_text(chat_id, text) do
    _token = Application.get_env(:island_pulse, :telegram)[:bot_token] || ""

    case TelegramBot.sendMessage(chat_id, text) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.error("Telegram send error: #{inspect(reason)}")
    end
  end

  # --- Alert Delivery ---

  @doc """
  Send a CRITICAL alert immediately.
  """
  def send_critical_alert(user_id, island_title, metric_name, value, direction, pct_change) do
    emoji = if direction == "down", do: "🔴", else: "🟢"
    arrow = if direction == "down", do: "↓", else: "↑"

    text = """
    #{emoji} CRITICAL ALERT — #{island_title}

    #{metric_name}: #{value} (#{arrow}#{pct_change}% from baseline)

    Check your dashboard for details.
    """

    send_text(user_id, text)
  end

  @doc """
  Send a daily summary to a user.
  """
  def send_daily_summary(user_id, island_title, metrics, alerts_today, tip \\ nil) do
    text =
      """
      📋 Daily Summary — #{island_title}

      Plays: #{format_number(metrics.plays)}
      Unique Players: #{format_number(metrics.unique_players)}
      Minutes Played: #{format_number(metrics.minutes_played)}
      """ <>
        if metrics.retention_d1 do
          "D1 Retention: #{Decimal.to_float(metrics.retention_d1)}%\n"
        else
          ""
        end <>
        if alerts_today > 0 do
          "\n⚠️ You had #{alerts_today} alert(s) today.\n"
        else
          "\n✅ No alerts today.\n"
        end <>
        if tip do
          "\n💡 Tip: #{tip}"
        else
          ""
        end

    send_text(user_id, text)
  end
end
