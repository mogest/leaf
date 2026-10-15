defmodule LeafWeb.ImpersonationController do
  @moduledoc """
  An administrator becoming somebody else, wherever config switches it on.

  It is for testing as people with other roles and standing. Everything done while impersonating
  is done as the person impersonated, so where it is switched off there is no starting it. Stopping
  always works, so switching it off strands nobody.
  """

  use LeafWeb, :controller

  require Logger

  alias Leaf.People
  alias LeafWeb.SignIn

  plug :require_enabled when action == :create

  @doc "Whether an administrator may impersonate here."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:leaf, __MODULE__)[:enabled] == true

  def create(%{assigns: %{current_person: %{id: id}}} = conn, %{"id" => id}) do
    redirect(conn, to: ~p"/people/#{id}")
  end

  def create(conn, %{"id" => id}) do
    case People.fetch_person(id) do
      {:ok, person} ->
        Logger.info("Person #{conn.assigns.current_person.id} is impersonating #{person.id}")
        conn |> SignIn.impersonate(person) |> redirect(to: ~p"/")

      :error ->
        redirect(conn, to: ~p"/people")
    end
  end

  def delete(conn, _params) do
    impersonated = conn.assigns.current_person

    conn |> SignIn.stop_impersonating() |> redirect(to: ~p"/people/#{impersonated}")
  end

  defp require_enabled(conn, _opts) do
    case enabled?() do
      true -> conn
      false -> raise Phoenix.Router.NoRouteError, conn: conn, router: LeafWeb.Router
    end
  end
end
