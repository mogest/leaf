defmodule LeafWeb.AuditLive do
  @moduledoc """
  Who changed what, with what it was before and what it became.

  Grants, accruals and expiries are not here: nobody performs them, they follow from somebody's
  dates, hours and policy, and they belong to the leave history. What is here is the change that
  caused them, and who made it.
  """

  use LeafWeb, :live_view

  alias Leaf.Audit
  alias Leaf.People

  @shown 100

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log")
     |> assign(:people, people(socket))
     |> assign(:form, to_form(%{"person_id" => ""}, as: :filter))
     |> listed(nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("filter", %{"filter" => %{"person_id" => id}}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(%{"person_id" => id}, as: :filter))
     |> listed(about(id))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Audit log</h1>
      </header>

      <Parts.settings_nav here="audit" />

      <.form id="filter" for={@form} phx-change="filter">
        <.input
          field={@form[:person_id]}
          type="select"
          label="About"
          prompt="Everybody"
          options={@people}
        />
      </.form>

      <section>
        <header>
          <h2>What has been changed</h2>
          <p>{@counted}</p>
        </header>
        <table :if={@entries != []}>
          <thead>
            <tr>
              <th scope="col">When</th>
              <th scope="col">What</th>
              <th scope="col">By</th>
              <th scope="col">About</th>
              <th scope="col">Changed</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={entry <- @entries}>
              <td>{entry.at}</td>
              <th scope="row">{entry.action}</th>
              <td>{entry.actor}</td>
              <td>{entry.subject}</td>
              <td>{entry.changed}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@entries == []}>Nothing has been recorded yet.</p>
      </section>
    </Layouts.app>
    """
  end

  defp people(socket) do
    socket.assigns.current_person.organisation_id
    |> People.people()
    |> Enum.map(&{&1.name, &1.id})
  end

  defp about(id) when id in [nil, ""], do: nil

  defp about(id) do
    {:ok, person} = People.fetch_person(id)

    person
  end

  defp listed(socket, nil) do
    shown(socket, Audit.entries(@shown))
  end

  defp listed(socket, person) do
    shown(socket, Audit.entries(person, @shown))
  end

  defp shown(socket, entries) do
    socket
    |> assign(:entries, Enum.map(entries, &row/1))
    |> assign(:counted, counted(entries))
  end

  defp counted([]), do: "nothing yet"
  defp counted([_one]), do: "one entry"
  defp counted(entries), do: "the #{length(entries)} most recent"

  defp row(entry) do
    %{
      at: Wording.moment(entry.inserted_at),
      action: said(entry.action),
      actor: Wording.actor(entry.actor),
      subject: entry.subject_person && entry.subject_person.name,
      changed: changed(entry.changes)
    }
  end

  # The action is written as a dotted path, which reads well enough said aloud once the dot goes.
  defp said(action) do
    action |> String.replace(".", " ") |> String.replace("_", " ")
  end

  defp changed(changes) do
    changes |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &String.replace(&1, "_", " "))
  end
end
