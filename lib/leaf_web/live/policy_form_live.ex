defmodule LeafWeb.PolicyFormLive do
  @moduledoc "Adding a policy, and renaming one."

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Org
  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case amending(socket.assigns.live_action, params) do
      {:ok, policy} -> {:ok, opened(socket, policy)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"leave_policy" => params}, socket) do
    changeset = change(socket.assigns.policy, socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"leave_policy" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/policies"}>Leave policies</.link>
          <.link :if={@policy} navigate={~p"/settings/policies/#{@policy}"}>{@policy.name}</.link>
        </nav>
        <h1>{@page_title}</h1>
      </header>

      <.form id="policy" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <.input field={@form[:name]} type="text" label="Name" />
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <.link navigate={back(@policy)}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp amending(:new, _params), do: {:ok, nil}
  defp amending(:edit, %{"id" => id}), do: Policies.fetch_leave_policy(id)

  defp opened(socket, policy) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    socket
    |> assign(:page_title, title(policy))
    |> assign(:policy, policy)
    |> assign(:organisation, organisation)
    |> assign(:form, to_form(change(policy, organisation, %{})))
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That policy is not on record.")
    |> push_navigate(to: ~p"/settings/policies")
  end

  defp title(nil), do: "Add a policy"
  defp title(policy), do: "Edit #{policy.name}"

  defp back(nil), do: ~p"/settings/policies"
  defp back(policy), do: ~p"/settings/policies/#{policy}"

  defp change(nil, organisation, params), do: Policies.change_leave_policy(organisation, params)
  defp change(policy, _organisation, params), do: Changeset.change(policy, params)

  defp write(%{policy: nil} = assigns, params) do
    Policies.create_leave_policy(assigns.organisation, assigns.current_person, params)
  end

  defp write(assigns, params) do
    Policies.update_leave_policy(assigns.policy, assigns.current_person, params)
  end

  defp saved(socket, {:ok, policy}) do
    socket |> put_flash(:info, "Saved.") |> push_navigate(to: ~p"/settings/policies/#{policy}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
