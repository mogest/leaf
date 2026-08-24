defmodule LeafWeb.HealthController do
  @moduledoc """
  Answers the cluster's two probes.

  Liveness asks whether the pod is worth keeping, and failing it restarts the pod, so it says only
  that the VM is up and serving. Readiness asks whether this pod can do anything useful, which
  means the database is answering; failing it takes the pod out of the Service and leaves it alone
  to recover.
  """

  use LeafWeb, :controller

  alias Leaf.Repo

  def show(conn, _params), do: send_resp(conn, 200, "ok")

  def ready(conn, _params), do: answered(conn, Repo.reachable?())

  defp answered(conn, true), do: send_resp(conn, 200, "ready")
  defp answered(conn, false), do: send_resp(conn, 503, "no database")
end
