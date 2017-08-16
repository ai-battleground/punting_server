defmodule PuntingServerWeb.PageController do
  use PuntingServerWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
