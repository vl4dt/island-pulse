defmodule IslandPulse.MetricsTest do
  use IslandPulse.DataCase, async: true

  alias IslandPulse.Metrics
  alias IslandPulse.Islands
  alias IslandPulse.Accounts.User

  describe "ewma/2" do
    test "returns nil for empty list" do
      assert Metrics.ewma([]) == nil
    end

    test "returns single value unchanged" do
      assert Metrics.ewma([10]) == 10
    end

    test "computes EWMA correctly with decay=0.3" do
      result = Metrics.ewma([10, 20, 30], 0.3)
      assert_in_delta(result, 18.1, 0.01)
    end

    test "computes EWMA with default decay" do
      result = Metrics.ewma([100, 200])
      assert_in_delta(result, 130.0, 0.01)
    end
  end

  describe "upsert_day_metric/2" do
    setup [:create_island]

    test "inserts a new day metric", %{island: island} do
      attrs = %{metric_date: Date.utc_today(), plays: 1000, unique_players: 500}

      assert {:ok, _metric} = Metrics.upsert_day_metric(island, attrs)
      assert Metrics.data_maturity_days(island) == 1
    end

    test "updates existing metric on conflict (idempotent upsert)", %{island: island} do
      date = Date.utc_today()

      {:ok, _} = Metrics.upsert_day_metric(island, %{metric_date: date, plays: 100})
      {:ok, updated} = Metrics.upsert_day_metric(island, %{metric_date: date, plays: 200})

      assert updated.plays == 200
      assert Metrics.data_maturity_days(island) == 1
    end
  end

  describe "data_maturity_days/1" do
    setup [:create_island_with_metrics]

    test "returns count of days with non-null plays", %{island: island} do
      assert Metrics.data_maturity_days(island) == 3
    end
  end

  describe "metric_median/3" do
    setup [:create_island_with_metrics]

    test "computes median of odd-length list", %{island: island} do
      # Our 3 days of data: 100, 200, 300 → median = 200
      median = Metrics.metric_median(island, :plays, 7)
      assert median == 200
    end

    test "returns nil when no data in range" do
      user = insert_user()

      {:ok, island} =
        Islands.get_or_create_island("MEDIAN_EMPTY_#{System.unique_integer([:positive])}", %{
          title: "Empty"
        })

      Islands.link_user_to_island(user, island, "primary")

      assert Metrics.metric_median(island, :plays, 7) == nil
    end
  end

  describe "latest_day_metrics/1" do
    setup [:create_island_with_metrics]

    test "returns the most recent day metric", %{island: island} do
      latest = Metrics.latest_day_metrics(island)
      assert latest.metric_date == Date.utc_today()
    end
  end

  describe "day_metrics_for_range/3" do
    setup [:create_island_with_metrics]

    test "returns metrics within the date range", %{island: island} do
      start = Date.add(Date.utc_today(), -2)
      end_date = Date.add(Date.utc_today(), -1)

      metrics = Metrics.day_metrics_for_range(island, start, end_date)
      assert length(metrics) == 2
    end
  end

  # --- Setup Helpers ---

  defp create_island(_context) do
    user = insert_user()

    {:ok, island} =
      Islands.get_or_create_island("METRICS_ISL_#{System.unique_integer([:positive])}", %{
        title: "Metrics Test"
      })

    Islands.link_user_to_island(user, island, "primary")
    %{island: island}
  end

  defp create_island_with_metrics(_context) do
    user = insert_user()

    {:ok, island} =
      Islands.get_or_create_island("METRICS_MATURE_#{System.unique_integer([:positive])}", %{
        title: "Mature"
      })

    Islands.link_user_to_island(user, island, "primary")

    # Insert 3 days of data using relative dates (so metric_median can find them)
    Metrics.upsert_day_metric(island, %{
      metric_date: Date.add(Date.utc_today(), -2),
      plays: 100,
      unique_players: 50
    })

    Metrics.upsert_day_metric(island, %{
      metric_date: Date.add(Date.utc_today(), -1),
      plays: 200,
      unique_players: 80
    })

    Metrics.upsert_day_metric(island, %{
      metric_date: Date.utc_today(),
      plays: 300,
      unique_players: 120
    })

    %{island: island}
  end

  defp insert_user do
    %User{}
    |> User.changeset(%{telegram_id: System.unique_integer([:positive]), tier: "free"})
    |> IslandPulse.Repo.insert!()
  end
end
