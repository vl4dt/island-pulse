defmodule IslandPulse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IslandPulseWeb.Telemetry,
      IslandPulse.Repo,
      {DNSCluster, query: Application.get_env(:island_pulse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: IslandPulse.PubSub},
      # Job queue
      {Oban, Application.fetch_env!(:island_pulse, Oban)},
      # Scheduler (only start if configured)
    ] ++ quantum_child() ++ [
      # Start to serve requests, typically the last entry
      IslandPulseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: IslandPulse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp quantum_child do
    case Application.get_env(:island_pulse, Quantum) do
      nil -> []
      config -> [{Quantum, config}]
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    IslandPulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
