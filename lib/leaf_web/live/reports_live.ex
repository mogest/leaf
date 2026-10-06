defmodule LeafWeb.ReportsLive do
  @moduledoc """
  The reports, a tab each, every one downloadable as a CSV of the rows it shows.

  What a report is asked for lives in the URL, so a report can be bookmarked or sent, and its
  download link is the same address with the file asked for instead of the page.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Reports

  @tabs [{"iPayroll export", "ipayroll"}]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Reports") |> assign(:tabs, @tabs)}
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
        <.link :if={@table} class="button" href={@download}>Download CSV</.link>
      </header>

      <nav class="tabs">
        <ul>
          <li :for={{label, report} <- @tabs}>
            <.link patch={~p"/reports/#{report}"} aria-current={report == @report && "page"}>
              {label}
            </.link>
          </li>
        </ul>
      </nav>

      <.form id="options" for={@form} phx-change="options">
        <.input field={@form[:from]} type="date" label="Requests starting from" />
        <.input field={@form[:to]} type="date" label="To" />
      </.form>

      <section :if={@table}>
        <p :for={note <- @table.notes}>{note}</p>
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

    socket
    |> assign(:report, report)
    |> assign(:form, to_form(changeset, as: :options, action: :validate))
    |> assign(:table, said(ran))
    |> assign(:download, ~p"/reports/#{report}/download?#{Map.delete(params, "report")}")
  end

  defp unknown(socket) do
    socket |> put_flash(:error, "There is no such report.") |> push_navigate(to: ~p"/reports")
  end

  defp said({:ok, table}),
    do: %{table | rows: Enum.map(table.rows, &Enum.map(&1, fn cell -> cell(cell) end))}

  defp said({:error, _changeset}), do: nil

  defp cell(%Date{} = date), do: Wording.brief_date(date)
  defp cell(%Decimal{} = amount), do: Wording.number(amount)
  defp cell(text), do: text
end
