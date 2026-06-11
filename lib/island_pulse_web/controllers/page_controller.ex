defmodule IslandPulseWeb.PageController do
  use IslandPulseWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
