defmodule IslandPulse.FortniteApi do
  @moduledoc """
  Client for the Fortnite Data API.
  Uses Req for HTTP requests with circuit breaker logic.
  """

  @circuit_key :island_pulse_circuit_breaker

  # --- Public API ---

  @doc """
  Fetch a list of islands with optional pagination.
  """
  def list_islands(size \\ 50, cursor \\ nil) do
    url = base_url() <> "/islands"

    query =
      %{"size" => size}
      |> maybe_put("cursor", cursor)

    get(url, query: query)
  end

  @doc """
  Fetch metrics for a specific island.
  """
  def fetch_metrics(island_code, interval \\ "day") do
    url = base_url() <> "/islands/#{URI.encode(island_code)}/metrics"

    query = %{"interval" => interval}

    get(url, query: query)
  end

  # --- Circuit Breaker ---

  @doc """
  Check if the circuit breaker is open (all polling paused).
  """
  def circuit_open? do
    case :persistent_term.get(@circuit_key, :closed) do
      {:open, until} -> NaiveDateTime.before?(NaiveDateTime.utc_now(), until)
      :closed -> false
    end
  end

  @doc """
  Open the circuit breaker for a given duration.
  """
  def open_circuit(duration_ms \\ 300_000) do
    until = NaiveDateTime.add(NaiveDateTime.utc_now(), duration_ms)
    :persistent_term.put(@circuit_key, {:open, until})
  end

  @doc """
  Close the circuit breaker.
  """
  def close_circuit do
    :persistent_term.put(@circuit_key, :closed)
  end

  # --- Parsing ---

  @doc """
  Parse an island list response into a list of maps.
  """
  def parse_island_list(%{"data" => islands}) when is_list(islands) do
    Enum.map(islands, fn island ->
      %{
        island_code: Map.get(island, "islandCode"),
        title: Map.get(island, "title"),
        creator_name: Map.get(island, "creatorName"),
        creation_tool: Map.get(island, "creationTool")
      }
    end)
  end

  def parse_island_list(_), do: []

  @doc """
  Parse metrics response into a list of metric maps.
  """
  def parse_metrics(%{"data" => data}) when is_map(data) do
    parse_metric_data(data)
  end

  def parse_metrics(_), do: []

  # --- HTTP Helpers ---

  defp get(url, opts) do
    case Req.get(url, opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 429}} ->
        pause_ms =
          Application.get_env(:island_pulse, :polling)[:circuit_breaker_pause_ms] || 300_000

        open_circuit(pause_ms)
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status}} when status >= 400 ->
        {:error, :http_error, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  # --- Metric Data Parsing ---

  defp parse_metric_data(data) do
    for {interval, records} <- data, is_list(records) do
      Enum.map(records, fn record ->
        %{
          interval: interval,
          plays: parse_int(Map.get(record, "plays")),
          unique_players: parse_int(Map.get(record, "uniquePlayers")),
          minutes_played: parse_int(Map.get(record, "minutesPlayed")),
          peak_ccu: parse_int(Map.get(record, "peakCCU")),
          favorites: parse_int(Map.get(record, "favorites")),
          recommendations: parse_int(Map.get(record, "recommendations")),
          retention_d1: parse_decimal(Map.get(record, "retention", %{}) |> Map.get("d1")),
          retention_d7: parse_decimal(Map.get(record, "retention", %{}) |> Map.get("d7")),
          metric_date: parse_metric_date(record)
        }
      end)
    end
    |> List.flatten()
  end

  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(val) when is_integer(val) or is_float(val), do: Decimal.new(val)

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.new(val) do
      %Decimal{} = d -> d
      _ -> nil
    end
  end

  defp parse_metric_date(%{"date" => date_str}) when is_binary(date_str) do
    case NaiveDateTime.from_iso8601(date_str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_metric_date(_), do: nil

  # --- Helpers ---

  defp base_url do
    Application.get_env(:island_pulse, :fortnite_api)[:base_url] ||
      "https://api.fortnite.com/ecosystem/v1"
  end
end
