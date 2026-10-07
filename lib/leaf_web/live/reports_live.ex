defmodule LeafWeb.ReportsLive do
  @moduledoc """
  The reports, a tab each, every one downloadable as a CSV of the rows it shows.

  What a report is asked for lives in the URL, so a report can be bookmarked or sent, and its
  download link is the same address with the file asked for instead of the page.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Reports

  # Each report, what it says, and the options it reads.
  @tabs [
    {"Leave taken", "taken",
     "Approved leave taken in the period, counting only its days that fall in it.",
     [:from, :to, :country_id, :leave_type_id]},
    {"Payroll reconciliation", "reconciliation",
     "Leave in the pay period filed, amended, approved or cancelled after the cut-off date.",
     [:from, :to, :cut_off]},
    {"Balances", "balances", "What everyone employed holds, each leave type in its own unit.",
     [:as_at]},
    {"Expiring soon", "expiring", "Leave that lapses within so many days unless it is taken.",
     [:as_at, :within]},
    {"iPayroll export", "ipayroll",
     "Approved requests whose first day falls in the period, each whole, as iPayroll's Leave " <>
       "Requests upload takes them.", [:from, :to]}
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    organisation_id = socket.assigns.current_person.organisation_id

    {:ok,
     socket
     |> assign(:page_title, "Reports")
     |> assign(:zone, People.time_zone(socket.assigns.current_person))
     |> assign(:tabs, Enum.map(@tabs, fn {label, report, _says, _fields} -> {label, report} end))
     |> assign(:countries, Enum.map(Org.countries(organisation_id), &{&1.name, &1.id}))
     |> assign(:leave_types, Enum.map(Policies.leave_types(organisation_id), &{&1.name, &1.id}))}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    person = socket.assigns.current_person
    changeset = Reports.change_options(person, params)

    case Keyword.has_key?(changeset.errors, :report) do
      true -> {:noreply, unknown(socket)}
      false -> {:noreply, shown(socket, changeset, Reports.run(person, params), params)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("options", %{"options" => options}, socket) do
    asked = Map.reject(options, fn {name, _value} -> String.starts_with?(name, "_unused_") end)

    {:noreply, push_patch(socket, to: ~p"/reports/#{socket.assigns.report}?#{asked}")}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="reports" viewer={@viewer}>
      <header>
        <h1>Reports</h1>
      </header>

      <nav class="tabs" aria-label="Reports">
        <ul>
          <li :for={{label, report} <- @tabs}>
            <.link patch={~p"/reports/#{report}"} aria-current={report == @report && "page"}>
              {label}
            </.link>
          </li>
        </ul>
      </nav>

      <p>{@says}</p>

      <.form id="options" for={@form} phx-change="options">
        <.input :if={:from in @fields} field={@form[:from]} type="date" label="From" />
        <.input :if={:to in @fields} field={@form[:to]} type="date" label="To" />
        <.input
          :if={:cut_off in @fields}
          field={@form[:cut_off]}
          type="date"
          label="Changed after"
        />
        <.input
          :if={:country_id in @fields}
          field={@form[:country_id]}
          type="select"
          label="Country"
          prompt="Every country"
          options={@countries}
        />
        <.input
          :if={:leave_type_id in @fields}
          field={@form[:leave_type_id]}
          type="select"
          label="Leave type"
          prompt="Every leave type"
          options={@leave_types}
        />
        <.input :if={:as_at in @fields} field={@form[:as_at]} type="date" label="As at" />
        <.input :if={:within in @fields} field={@form[:within]} type="number" label="Days ahead" />
        <.link :if={@table} class="button" href={@download}>Download CSV</.link>
      </.form>

      <section :if={@table}>
        <p :for={note <- @table.notes}>
          <svg
            width="16"
            height="16"
            viewBox="0 0 16 16"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-label="Warning"
            role="img"
          >
            <path d="M8 2L1.5 13.5h13L8 2zM8 6.5v3.5M8 12v.01" />
          </svg>
          {note}
        </p>
        <div :if={@table.rows != []}>
          <table>
            <thead>
              <tr>
                <th :for={column <- @table.columns} scope="col">{column}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @table.rows}>
                <td :for={cell <- row}>{cell}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@table.rows == []}>Nothing to report.</p>
      </section>
    </Layouts.app>
    """
  end

  defp shown(socket, changeset, ran, params) do
    report = to_string(Ecto.Changeset.get_field(changeset, :report))
    {_label, _report, says, fields} = List.keyfind(@tabs, report, 1)

    socket
    |> assign(:report, report)
    |> assign(:says, says)
    |> assign(:fields, fields)
    |> assign(:form, to_form(changeset, as: :options, action: :validate))
    |> assign(:table, said(ran, socket.assigns.zone))
    |> assign(:download, ~p"/reports/#{report}/download?#{Map.delete(params, "report")}")
  end

  defp unknown(socket) do
    socket |> put_flash(:error, "There is no such report.") |> push_navigate(to: ~p"/reports")
  end

  defp said({:ok, table}, zone) do
    %{table | rows: Enum.map(table.rows, &Enum.map(&1, fn cell -> cell(cell, zone) end))}
  end

  defp said({:error, _changeset}, _zone), do: nil

  defp cell(%Date{} = date, _zone), do: Wording.brief_date(date)
  defp cell(%DateTime{} = at, zone), do: Wording.moment(at, zone)
  defp cell(%Decimal{} = amount, _zone), do: Wording.number(amount)
  defp cell(text, _zone), do: text
end
