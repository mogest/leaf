defmodule LeafWeb.PolicyFormLive do
  @moduledoc "Renaming a policy."

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Policies.fetch_leave_policy(id) do
      {:ok, policy} -> {:ok, opened(socket, policy)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"leave_policy" => params}, socket) do
    changeset = Changeset.change(socket.assigns.policy, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"leave_policy" => params}, socket) do
    written =
      Policies.update_leave_policy(socket.assigns.policy, socket.assigns.current_person, params)

    {:noreply, saved(socket, written)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/policies"}>Leave policies</.link>
          <.link navigate={~p"/settings/policies/#{@policy}"}>{@policy.name}</.link>
        </nav>
        <h1>Edit the policy</h1>
      </header>

      <.form id="policy" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <.input field={@form[:name]} type="text" label="Name" />
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/settings/policies/#{@policy}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp opened(socket, policy) do
    socket
    |> assign(:page_title, "Edit #{policy.name}")
    |> assign(:policy, policy)
    |> assign(:form, to_form(Changeset.change(policy, %{})))
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That policy is not on record.")
    |> push_navigate(to: ~p"/settings/policies")
  end

  defp saved(socket, {:ok, policy}) do
    socket |> put_flash(:info, "Saved.") |> push_navigate(to: ~p"/settings/policies/#{policy}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
