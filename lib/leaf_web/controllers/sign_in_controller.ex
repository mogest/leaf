defmodule LeafWeb.SignInController do
  @moduledoc """
  Signing in through the organisation's identity provider.

  The provider is an `Assent` strategy named in config, alongside its credentials, so changing
  provider is a change of config. All Leaf asks of one is a verified email address, and somebody
  may sign in only where a person has it.
  """

  use LeafWeb, :controller

  require Logger

  alias Leaf.People
  alias LeafWeb.SignIn
  alias LeafWeb.SignInPickerController

  @pending "sign_in"

  def index(conn, _params) do
    render(conn, :index, page_title: "Sign in", picker?: SignInPickerController.enabled?())
  end

  def start(conn, _params) do
    {strategy, config} = provider()
    {:ok, %{url: url, session_params: session_params}} = strategy.authorize_url(config)

    conn |> put_session(@pending, session_params) |> redirect(external: url)
  end

  def callback(conn, params) do
    session_params = get_session(conn, @pending)
    conn = delete_session(conn, @pending)

    case verified_email(session_params, params) do
      {:ok, email} -> sign_in_as(conn, email)
      :error -> refuse(conn, "Signing in didn't work. Try again.")
    end
  end

  def delete(conn, _params), do: conn |> SignIn.sign_out() |> redirect(to: ~p"/sign-in")

  defp verified_email(nil, _params), do: :error

  defp verified_email(session_params, params) do
    {strategy, config} = provider()

    case strategy.callback([{:session_params, session_params} | config], params) do
      {:ok, %{user: %{"email" => email, "email_verified" => true}}} ->
        {:ok, email}

      {:ok, _unverified} ->
        Logger.warning("Sign-in refused an unverified address")
        :error

      {:error, error} ->
        Logger.warning("Sign-in failed: #{reason(error)}")
        :error
    end
  end

  defp reason(error) when is_exception(error), do: Exception.message(error)
  defp reason(error), do: inspect(error)

  defp sign_in_as(conn, email) do
    case People.fetch_person_by_email(email) do
      {:ok, person} -> conn |> SignIn.sign_in(person) |> redirect(to: ~p"/")
      :error -> refuse(conn, "Nobody in Leaf has the address #{email}.")
    end
  end

  defp refuse(conn, message), do: conn |> put_flash(:error, message) |> redirect(to: ~p"/sign-in")

  defp provider do
    {strategy, config} = :leaf |> Application.fetch_env!(__MODULE__) |> Keyword.pop!(:strategy)
    {strategy, Keyword.put(config, :redirect_uri, url(~p"/sign-in/callback"))}
  end
end
