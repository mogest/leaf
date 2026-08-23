defmodule LeafWeb.HealthController do
  @moduledoc "Answers the cluster's readiness probe."

  use LeafWeb, :controller

  def show(conn, _params), do: send_resp(conn, 200, "ok")
end
