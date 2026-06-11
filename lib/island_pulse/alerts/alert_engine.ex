defmodule IslandPulse.Alerts.AlertEngine do
  @moduledoc """
  Evaluates alert thresholds for island metrics.
  Uses median baseline + EWMA trend with dynamic maturity thresholds.
  """
  import Ecto.Query
  alias IslandPulse.Repo
  alias IslandPulse.Metrics.MetricDay
  alias IslandPulse.Metrics
  alias IslandPulse.Alerts.Alert

  @metric_fields [:plays, :unique_players, :minutes_played, :peak_ccu, :favorites]
  @retention_fields [:retention_d1, :retention_d7]
  @all_fields @metric_fields ++ @retention_fields

  @doc """
  Evaluate alerts for an island after a new metric poll.
  Returns list of alert maps to be delivered.
  """
  def evaluate(island) do
    maturity = Metrics.data_maturity_days(island)
    thresholds = get_thresholds(maturity)

    # Only evaluate if we have at least 2 days of data
    if maturity < 2 do
      []
    else
      field_alerts =
        Enum.flat_map(@all_fields, fn field ->
          baseline = Metrics.metric_median(island, field, 7)
          latest = get_latest_value(island, field)

          if not is_nil(baseline) and not is_nil(latest) and baseline > 0 do
            pct_change = pct_diff(latest, baseline)

            case determine_severity(pct_change, thresholds, field) do
              {severity, direction} ->
                cooldown_ok = check_cooldown(island, field, severity, latest, pct_change)

                if cooldown_ok do
                  [
                    %{
                      island_id: island.id,
                      severity: severity,
                      metric_name: to_string(field),
                      value: Decimal.new(latest),
                      threshold_pct: Decimal.new(abs(pct_change)),
                      direction: direction,
                      sent_at: NaiveDateTime.utc_now()
                    }
                  ]
                else
                  []
                end

              :none ->
                []
            end
          else
            []
          end
        end)

      # Check for dead island (null data)
      dead_alerts = check_dead_island(island)
      field_alerts ++ dead_alerts
    end
  end

  @doc """
  Save an alert to the database.
  """
  def save_alert(user, alert_map) do
    changeset = %Alert{user_id: user.id} |> Map.merge(alert_map) |> Alert.changeset(%{})
    Repo.insert(changeset)
  end

  @doc """
  Get recent alerts for a user and island.
  """
  def recent_alerts(user, island, hours \\ 24) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -hours * 3600)

    from(a in Alert,
      where: a.user_id == ^user.id and a.island_id == ^island.id and a.sent_at >= ^cutoff,
      order_by: [desc: a.sent_at]
    )
    |> Repo.all()
  end

  # --- Private Helpers ---

  defp get_thresholds(maturity_days) do
    config = Application.get_env(:island_pulse, :alerts)[:thresholds] || %{}

    case maturity_days do
      d when d >= 31 -> Map.get(config, "stable", %{critical: 25, warning: 15})
      d when d >= 15 -> Map.get(config, "forming", %{critical: 35, warning: 20})
      _ -> Map.get(config, "noisy", %{critical: 50, warning: 25})
    end
  end

  defp pct_diff(current, baseline) do
    (current - baseline) / baseline * 100
  end

  defp determine_severity(pct_change, thresholds, _field) do
    abs_pct = abs(pct_change)

    # For retention fields: drop is bad, increase is good
    # For engagement fields (plays, unique_players): drop is bad, increase is good
    if pct_change < 0 do
      # Metric dropped
      cond do
        abs_pct >= thresholds.critical -> {:critical, "down"}
        abs_pct >= thresholds.warning -> {:warning, "down"}
        true -> :none
      end
    else
      # Metric increased — positive alert (info level)
      if abs_pct >= thresholds.warning do
        {:info, "up"}
      else
        :none
      end
    end
  end

  defp check_cooldown(island, field, severity, _current_value, pct_change) do
    case severity do
      "critical" ->
        cooldown_hours = Application.get_env(:island_pulse, :alerts)[:cooldown_hours] || 24
        override_pct = Application.get_env(:island_pulse, :alerts)[:cooldown_override_pct] || 5

        cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -cooldown_hours * 3600)

        last_alert =
          from(a in Alert,
            where:
              a.island_id == ^island.id and a.metric_name == ^to_string(field) and
                a.severity == "critical",
            order_by: [desc: a.sent_at],
            limit: 1
          )
          |> Repo.one()

        cond do
          is_nil(last_alert) -> true
          NaiveDateTime.before?(last_alert.sent_at, cutoff) -> true
          # Override: metric worsened by >5% since last alert
          abs(pct_change) > Decimal.to_float(last_alert.threshold_pct) + override_pct -> true
          # Override: metric recovered (direction changed from down to up)
          pct_change > 0 -> true
          true -> false
        end

      _ ->
        # No cooldown for non-critical alerts
        true
    end
  end

  defp get_latest_value(island, field) do
    case Repo.one(
           from(m in MetricDay,
             where: m.island_id == ^island.id and not is_nil(field(m, ^field)),
             order_by: [desc: m.metric_date],
             limit: 1,
             select: field(m, ^field)
           )
         ) do
      %Decimal{} = d -> Decimal.to_float(d)
      val when is_number(val) -> val
      _ -> nil
    end
  end

  defp check_dead_island(island) do
    # Check if the island was previously active but now returns null
    latest = Metrics.latest_day_metrics(island)

    case latest do
      %MetricDay{plays: nil} ->
        # Check if there was data before
        maturity = Metrics.data_maturity_days(island)

        if maturity > 0 do
          # Island was active but now has null data
          [
            %{
              island_id: island.id,
              severity: "critical",
              metric_name: "dead_island",
              value: nil,
              threshold_pct: nil,
              direction: "down",
              sent_at: NaiveDateTime.utc_now()
            }
          ]
        else
          []
        end

      _ ->
        []
    end
  end
end
