defmodule LeafWeb.PageController do
  use LeafWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
