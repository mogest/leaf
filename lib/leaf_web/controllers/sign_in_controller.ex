defmodule LeafWeb.SignInController do
  @moduledoc "Picking who you are, until there is real authentication. See `LeafWeb.SignIn`."

  use LeafWeb, :controller

  alias Leaf.Org
  alias Leaf.People
  alias LeafWeb.SignIn

  def index(conn, _params) do
    render(conn, :index, page_title: "Sign in", people: everybody())
  end

  def create(conn, %{"id" => id}) do
    case People.fetch_person(id) do
      {:ok, person} -> conn |> SignIn.sign_in(person) |> redirect(to: ~p"/")
      :error -> redirect(conn, to: ~p"/sign-in")
    end
  end

  def delete(conn, _params), do: conn |> SignIn.sign_out() |> redirect(to: ~p"/sign-in")

  # One organisation in v1, and it is whichever one there is.
  defp everybody do
    case Org.organisations() do
      [organisation | _rest] -> People.people(organisation.id)
      [] -> []
    end
  end
end
