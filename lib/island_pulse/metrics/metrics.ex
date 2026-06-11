defmodule IslandPulse.Metrics do
  import Ecto.Query
  alias IslandPulse.Repo
  alias IslandPulse.Metrics.{MetricDay, MetricHour, MetricMinute}

  @doc """
  Upsert a day-level metric for an island.
  Uses ON CONFLICT to update existing records.
  """
  def upsert_day_metric(island, attrs) do
    changeset = %MetricDay{island_id: island.id} |> MetricDay.changeset(attrs)

    Repo.insert(changeset,
      conflict_target: [:island_id, :metric_date],
      on_conflict: [
        set: [
          :plays,
          :unique_players,
          :minutes_played,
          :peak_ccu,
          :favorites,
          :recommendations,
          :retention_d1,
          :retention_d7
        ]
      ],
      prefix: "public"
    )
  end

  @doc """
  Upsert an hour-level metric for an island.
  """
  def upsert_hour_metric(island, attrs) do
    changeset = %MetricHour{island_id: island.id} |> MetricHour.changeset(attrs)

    Repo.insert(changeset,
      conflict_target: [:island_id, :metric_date],
      on_conflict: [
        set: [:plays, :unique_players, :minutes_played, :peak_ccu, :favorites, :recommendations]
      ],
      prefix: "public"
    )
  end

  @doc """
  Upsert a minute-level metric for an island.
  """
  def upsert_minute_metric(island, attrs) do
    changeset = %MetricMinute{island_id: island.id} |> MetricMinute.changeset(attrs)

    Repo.insert(changeset,
      conflict_target: [:island_id, :metric_date],
      on_conflict: [
        set: [:plays, :unique_players, :minutes_played, :peak_ccu, :favorites, :recommendations]
      ],
      prefix: "public"
    )
  end

  @doc """
  Get the latest day-level metrics for an island.
  """
  def latest_day_metrics(island) do
    from(m in MetricDay,
      where: m.island_id == ^island.id,
      order_by: [desc: m.metric_date],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Get day-level metrics for an island within a date range.
  """
  def day_metrics_for_range(island, start_date, end_date) do
    from(m in MetricDay,
      where:
        m.island_id == ^island.id and m.metric_date >= ^start_date and m.metric_date <= ^end_date,
      order_by: [asc: m.metric_date]
    )
    |> Repo.all()
  end

  @doc """
  Get hour-level metrics for an island within a time range.
  """
  def hour_metrics_for_range(island, start_time, end_time) do
    from(m in MetricHour,
      where:
        m.island_id == ^island.id and m.metric_date >= ^start_time and m.metric_date <= ^end_time,
      order_by: [asc: m.metric_date]
    )
    |> Repo.all()
  end

  @doc """
  Get the number of days of data for an island (data maturity).
  """
  def data_maturity_days(island) do
    from(m in MetricDay,
      where: m.island_id == ^island.id and not is_nil(m.plays),
      select: count(m.metric_date)
    )
    |> Repo.one()
  end

  @doc """
  Get the median value for a metric over the last N days.
  Used as baseline for alert thresholds.
  """
  def metric_median(island, metric_field, days \\ 7) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 24 * 3600)

    values =
      from(m in MetricDay,
        where:
          m.island_id == ^island.id and m.metric_date >= ^cutoff and
            not is_nil(field(m, ^metric_field)),
        select: field(m, ^metric_field)
      )
      |> Repo.all()

    case values do
      [] -> nil
      _ -> Enum.sort(values) |> median()
    end
  end

  @doc """
  Compute EWMA (Exponentially Weighted Moving Average) over a list of values.
  Decay factor controls how much weight recent values have.
  """
  def ewma(values, decay \\ 0.3) do
    case values do
      [] ->
        nil

      [v] ->
        v

      _ ->
        Enum.reduce(values, {nil, nil}, fn value, {prev_ewma, _} ->
          if is_nil(prev_ewma) do
            {value, value}
          else
            ewma = decay * value + (1 - decay) * prev_ewma
            {ewma, ewma}
          end
        end)
        |> elem(0)
    end
  end

  @doc """
  Clean up old hour-level metrics beyond retention period.
  """
  def cleanup_hour_metrics(retention_days \\ 30) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -retention_days * 24 * 3600)

    Repo.delete_all(from(m in MetricHour, where: m.metric_date < ^cutoff))
  end

  @doc """
  Clean up old minute-level metrics beyond retention period.
  """
  def cleanup_minute_metrics(retention_days \\ 7) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -retention_days * 24 * 3600)

    Repo.delete_all(from(m in MetricMinute, where: m.metric_date < ^cutoff))
  end

  defp median(values) when is_list(values) and length(values) > 0 do
    sorted = Enum.sort(values)
    mid = div(length(sorted), 2)

    case rem(length(sorted), 2) do
      1 -> Enum.at(sorted, mid)
      0 -> (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end
end
