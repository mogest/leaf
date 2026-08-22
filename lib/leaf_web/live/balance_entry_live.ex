defmodule LeafWeb.BalanceEntryLive do
  @moduledoc """
  Recording a balance nothing else can account for: an opening import, or an adjustment.

  Everything else about a balance follows from the person's dates, hours and policy. These two are
  the only movements no configuration produces, which is why they are the only ones typed in. An
  adjustment needs a reason; an opening balance is its own explanation.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.People
  alias Leaf.Policies

  @kinds [
    {"Opening balance — what they held when tracking began", "opening_balance"},
    {"Adjustment — a correction, with a reason", "adjustment"}
  ]

  @impl Phoenix.LiveView
  def mount(%{"person_id" => id}, _session, socket) do
    {:ok, person} = People.fetch_person(id)
    opening = %{"kind" => "opening_balance", "date" => to_string(Date.utc_today())}

    {:ok,
     socket
     |> assign(:page_title, "Record a balance")
     |> assign(:person, person)
     |> assign(:kinds, @kinds)
     |> assign(:leave_types, leave_types(person))
     |> assign(:form, to_form(Leave.change_balance_entry(person, opening)))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"balance_entry" => params}, socket) do
    changeset = Leave.change_balance_entry(socket.assigns.person, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"balance_entry" => params}, socket) do
    entry =
      Leave.create_balance_entry(socket.assigns.person, socket.assigns.current_person, params)

    {:noreply, saved(socket, entry)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <h1>Record a balance</h1>
        <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
      </header>

      <.form id="balance-entry" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>What is being recorded</h2>
          </header>
          <.input field={@form[:kind]} type="select" label="What it is" options={@kinds} />
          <.input
            field={@form[:leave_type_id]}
            type="select"
            label="Leave type"
            prompt="Choose one"
            options={@leave_types}
          />
          <.input field={@form[:date]} type="date" label="Dated" />
          <.input field={@form[:amount]} type="text" label="Amount, negative to take away" />
          <.input field={@form[:expires_on]} type="date" label="Lapses on, if it lapses" />
          <.input field={@form[:reason]} type="textarea" label="Reason" />
        </section>

        <footer>
          <button class="button" type="submit">Record it</button>
          <.link navigate={~p"/people/#{@person}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp leave_types(person) do
    person.organisation_id
    |> Policies.leave_types()
    |> Enum.filter(&is_nil(&1.archived_at))
    |> Enum.map(&{Wording.leave_type(&1), &1.id})
  end

  defp saved(socket, {:ok, _entry}) do
    socket
    |> put_flash(:info, "It is on the record.")
    |> push_navigate(to: ~p"/people/#{socket.assigns.person}")
  end

  defp saved(socket, {:error, :forbidden}) do
    put_flash(socket, :error, "Only an administrator may record a balance.")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
