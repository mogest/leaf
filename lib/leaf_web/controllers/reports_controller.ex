defmodule LeafWeb.ReportsController do
  @moduledoc """
  A report as a CSV file, being the rows its page shows.

  A LiveView cannot send a file, so the page's download link comes here with the same params.
  """

  use LeafWeb, :controller

  alias Leaf.People
  alias Leaf.Reports

  def download(conn, %{"report" => report} = params) do
    person = conn.assigns.current_person

    case Reports.run(person, params) do
      {:ok, table} ->
        send_download(conn, {:binary, Reports.csv(table, People.time_zone(person))},
          filename: "#{report}.csv",
          content_type: "text/csv"
        )

      {:error, _changeset} ->
        send_resp(conn, 400, "That report cannot be run as asked.")
    end
  end
end
