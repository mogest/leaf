defmodule LeafWeb.AuditLive do
  @moduledoc """
  Who changed what, with what it was before and what it became.

  Grants, accruals and expiries are not here: nobody performs them, they follow from somebody's
  dates, hours and policy, and they belong to the leave history. What is here is the change that
  caused them, and who made it.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Ecto.Changeset
  alias Leaf.Audit
  alias Leaf.People

  @shown 100
  @params %{about: Ecto.UUID, through: :date, page: :integer}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log")
     |> assign(:people, people(socket))}
  end

  # What does not read as a filter, or names somebody not offered, is left out, so the log reads as
  # it does unfiltered.
  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    changeset =
      {%{}, @params}
      |> Changeset.cast(params, Map.keys(@params))
      |> Changeset.validate_inclusion(:about, Enum.map(socket.assigns.people, &elem(&1, 1)))

    asked = Map.drop(changeset.changes, Keyword.keys(changeset.errors))
    kept = Map.take(params, Enum.map(Map.keys(asked), &to_string/1))
    zone = socket.assigns.zone
    filter = [about: asked[:about], through: asked[:through], zone: zone]
    page = Audit.page(filter, Map.get(asked, :page, 1), @shown)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :filter))
     |> assign(:entries, Enum.map(page.entries, &row(&1, zone)))
     |> assign(:paging, %{
       page: page.page,
       pages: page.pages,
       newer: page.page > 1 && paged(kept, page.page - 1),
       older: page.page < page.pages && paged(kept, page.page + 1)
     })}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("filter", %{"filter" => filter}, socket) do
    asked =
      for {name, value} <- Map.take(filter, ~w(about through)),
          value != "",
          into: %{},
          do: {name, value}

    {:noreply, push_patch(socket, to: ~p"/settings/audit?#{asked}")}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="audit" viewer={@viewer}>
      <header>
        <h1>Audit log</h1>
      </header>

      <Parts.settings_nav here="audit" />

      <.form id="filter" for={@form} phx-change="filter">
        <.input
          field={@form[:about]}
          type="select"
          label="About"
          prompt="Everybody"
          options={@people}
        />
        <.input field={@form[:through]} type="date" label="Up to" />
        <.pages paging={@paging} label="Pages at the top" />
      </.form>

      <div :if={@entries != []}>
        <table>
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
      </div>
      <p :if={@entries == []}>Nothing has been recorded.</p>

      <.pages paging={@paging} label="Pages at the bottom" />
    </Layouts.app>
    """
  end

  attr :paging, :map, required: true
  attr :label, :string, required: true

  defp pages(assigns) do
    ~H"""
    <nav :if={@paging.pages > 1} aria-label={@label}>
      <.link :if={@paging.newer} navigate={@paging.newer}>Newer</.link>
      <a :if={!@paging.newer}>Newer</a>
      <span>Page {@paging.page} of {@paging.pages}</span>
      <.link :if={@paging.older} navigate={@paging.older}>Older</.link>
      <a :if={!@paging.older}>Older</a>
    </nav>
    """
  end

  defp people(socket) do
    socket.assigns.current_person.organisation_id
    |> People.everybody()
    |> Enum.map(&{&1.name, &1.id})
  end

  defp paged(kept, page), do: ~p"/settings/audit?#{Map.put(kept, "page", page)}"

  defp row(entry, zone) do
    %{
      at: Wording.moment(entry.inserted_at, zone),
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
