defmodule LeafWeb.SignInPickerController do
  @moduledoc """
  Signing in as anybody by picking them off a list, in development.

  Seeded people have made-up addresses no identity provider will vouch for, so this is how a
  developer becomes them. It verifies nothing, so outside development it is not found.
  """

  use LeafWeb, :controller

  alias Leaf.Org
  alias Leaf.People
  alias LeafWeb.SignIn

  plug :require_enabled

  @doc "Whether picking somebody is allowed here."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:leaf, :dev_routes) == true

  def index(conn, _params) do
    render(conn, :index, page_title: "Sign in", people: everybody())
  end

  def create(conn, %{"id" => id}) do
    case People.fetch_unarchived_person(id) do
      {:ok, person} -> conn |> SignIn.sign_in(person) |> redirect(to: ~p"/")
      :error -> redirect(conn, to: ~p"/sign-in/pick")
    end
  end

  defp require_enabled(conn, _opts) do
    case enabled?() do
      true -> conn
      false -> raise Phoenix.Router.NoRouteError, conn: conn, router: LeafWeb.Router
    end
  end

  # One organisation in v1, and it is whichever one there is.
  defp everybody do
    case Org.organisations() do
      [organisation | _rest] -> People.people(organisation.id)
      [] -> []
    end
  end
end
