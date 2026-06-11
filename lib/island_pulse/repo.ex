defmodule IslandPulse.Repo do
  use Ecto.Repo,
    otp_app: :island_pulse,
    adapter: Ecto.Adapters.Postgres
end
