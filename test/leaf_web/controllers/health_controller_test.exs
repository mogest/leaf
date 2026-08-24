defmodule LeafWeb.HealthControllerTest do
  use LeafWeb.ConnCase, async: true

  test "liveness answers as long as the pod is serving", %{conn: conn} do
    assert response(get(conn, ~p"/healthz"), 200) == "ok"
  end

  test "readiness answers while the database does", %{conn: conn} do
    assert response(get(conn, ~p"/healthz/ready"), 200) == "ready"
  end

  test "readiness refuses where the database does not answer", %{conn: conn} do
    assert response(without_database(fn -> get(conn, ~p"/healthz/ready") end), 503) ==
             "no database"
  end

  # Nothing in a test can take the database away, so the request is made from a process the sandbox
  # has lent no connection to, which is what a pod that has lost its database looks like.
  defp without_database(request) do
    test = self()

    spawn(fn -> send(test, {:answered, request.()}) end)

    receive do
      {:answered, conn} -> conn
    after
      1_000 -> flunk("the probe never answered")
    end
  end
end
