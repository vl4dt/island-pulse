defmodule IslandPulseWeb.Router do
  use IslandPulseWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IslandPulseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", IslandPulseWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # LiveDashboard for admin (dev only for now)
  if Application.compile_env(:island_pulse, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    live_dashboard "/dashboard",
      metrics: IslandPulseWeb.Telemetry,
      extra_metrics: []

    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
