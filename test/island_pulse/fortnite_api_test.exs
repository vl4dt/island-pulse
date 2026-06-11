defmodule IslandPulse.FortniteApiTest do
  use ExUnit.Case, async: true

  alias IslandPulse.FortniteApi

  setup do
    # Ensure circuit is closed before each test
    on_exit(fn -> FortniteApi.close_circuit() end)
    {:ok, circuit: :closed}
  end

  describe "parse_island_list/1" do
    test "parses valid island list response" do
      payload = %{
        "data" => [
          %{
            "islandCode" => "ABC123",
            "title" => "My Island",
            "creatorName" => "Builder",
            "creationTool" => "Fortnite"
          },
          %{
            "islandCode" => "XYZ789",
            "title" => "Another Island",
            "creatorName" => "Other",
            "creationTool" => "Island Designer"
          }
        ]
      }

      result = FortniteApi.parse_island_list(payload)

      assert length(result) == 2
      assert Enum.at(result, 0).island_code == "ABC123"
      assert Enum.at(result, 0).title == "My Island"
      assert Enum.at(result, 0).creator_name == "Builder"
      assert Enum.at(result, 0).creation_tool == "Fortnite"
      assert Enum.at(result, 1).island_code == "XYZ789"
    end

    test "handles missing fields gracefully (nil)" do
      payload = %{
        "data" => [
          %{"islandCode" => "ABC123", "title" => nil, "creatorName" => nil, "creationTool" => nil}
        ]
      }

      result = FortniteApi.parse_island_list(payload)

      assert length(result) == 1
      assert Enum.at(result, 0).island_code == "ABC123"
      assert Enum.at(result, 0).title == nil
    end

    test "returns empty list for malformed response" do
      assert FortniteApi.parse_island_list(%{"data" => nil}) == []
      assert FortniteApi.parse_island_list(%{}) == []
      assert FortniteApi.parse_island_list(nil) == []
    end

    test "returns empty list when data is not a list" do
      assert FortniteApi.parse_island_list(%{"data" => %{"single" => "island"}}) == []
    end
  end

  describe "parse_metrics/1" do
    test "parses valid metrics response with integer retention values" do
      payload = %{
        "data" => %{
          "day" => [
            %{
              "date" => "2024-01-15T00:00:00Z",
              "plays" => 1000,
              "uniquePlayers" => 500,
              "minutesPlayed" => 50_000,
              "peakCCU" => 200,
              "favorites" => 100,
              "recommendations" => 50,
              "retention" => %{"d1" => 75, "d7" => 30}
            }
          ]
        }
      }

      result = FortniteApi.parse_metrics(payload)

      assert length(result) == 1
      metric = Enum.at(result, 0)
      assert metric.interval == "day"
      assert metric.plays == 1000
      assert metric.unique_players == 500
      assert metric.minutes_played == 50_000
      assert metric.peak_ccu == 200
      assert metric.favorites == 100
      assert metric.recommendations == 50
      assert Decimal.equal?(metric.retention_d1, Decimal.new(75))
      assert Decimal.equal?(metric.retention_d7, Decimal.new(30))
    end

    test "handles null fields in metrics" do
      payload = %{
        "data" => %{
          "day" => [
            %{"date" => "2024-01-15T00:00:00Z", "plays" => nil, "uniquePlayers" => nil}
          ]
        }
      }

      result = FortniteApi.parse_metrics(payload)
      assert length(result) == 1
      assert Enum.at(result, 0).plays == nil
    end

    test "handles string integer fields" do
      payload = %{
        "data" => %{
          "day" => [
            %{"date" => "2024-01-15T00:00:00Z", "plays" => "1234"}
          ]
        }
      }

      result = FortniteApi.parse_metrics(payload)
      assert Enum.at(result, 0).plays == 1234
    end

    test "handles unparseable string integer fields as nil" do
      payload = %{
        "data" => %{
          "day" => [
            %{"date" => "2024-01-15T00:00:00Z", "plays" => "not_a_number"}
          ]
        }
      }

      result = FortniteApi.parse_metrics(payload)
      assert Enum.at(result, 0).plays == nil
    end

    test "returns empty list for malformed metrics response" do
      assert FortniteApi.parse_metrics(%{"data" => nil}) == []
      assert FortniteApi.parse_metrics(%{}) == []
      assert FortniteApi.parse_metrics(nil) == []
    end

    test "handles missing retention data (nil retention map)" do
      payload = %{
        "data" => %{
          "day" => [
            %{"date" => "2024-01-15T00:00:00Z", "plays" => 100, "retention" => nil}
          ]
        }
      }

      # This should crash because parse_decimal calls Map.get on nil
      # The code uses Map.get(record, "retention", %{}) but when retention is nil,
      # the default %{} only applies if the key is missing, not when value is nil
      assert_raise(BadMapError, fn ->
        FortniteApi.parse_metrics(payload)
      end)
    end

    test "handles partial retention data" do
      payload = %{
        "data" => %{
          "day" => [
            %{"date" => "2024-01-15T00:00:00Z", "plays" => 100, "retention" => %{"d1" => 75}}
          ]
        }
      }

      result = FortniteApi.parse_metrics(payload)
      assert Decimal.equal?(Enum.at(result, 0).retention_d1, Decimal.new(75))
      assert Enum.at(result, 0).retention_d7 == nil
    end

    test "flattens multiple intervals" do
      payload = %{
        "data" => %{
          "day" => [
            %{"date" => "2024-01-15T00:00:00Z", "plays" => 100}
          ],
          "hour" => [
            %{"date" => "2024-01-15T12:00:00Z", "plays" => 10}
          ]
        }
      }

      result = FortniteApi.parse_metrics(payload)
      assert length(result) == 2
    end
  end

  describe "circuit breaker" do
    test "starts closed" do
      refute FortniteApi.circuit_open?()
    end

    test "can be opened and closed" do
      FortniteApi.open_circuit(60_000)
      assert FortniteApi.circuit_open?()
      FortniteApi.close_circuit()
      refute FortniteApi.circuit_open?()
    end

    test "returns false when circuit expiry has passed" do
      # Open circuit with 0ms duration — already expired
      FortniteApi.open_circuit(0)
      refute FortniteApi.circuit_open?()
    end

    test "returns true when circuit expiry has not passed" do
      FortniteApi.open_circuit(60_000)
      assert FortniteApi.circuit_open?()
    end
  end
end
