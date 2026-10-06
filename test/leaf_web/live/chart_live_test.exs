defmodule LeafWeb.ChartLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures

  test "everyone reads the chart, opening only the records they oversee", %{conn: conn} do
    organisation = Fixtures.organisation()
    manager = Fixtures.person(%{organisation_id: organisation.id, name: "Ines Vasquez"})

    report =
      Fixtures.person(%{
        organisation_id: organisation.id,
        name: "Bo Ngata",
        manager_id: manager.id
      })

    {:ok, _live, html} = live(sign_in(conn, report), ~p"/chart")

    assert html =~ ~s(href="/chart")
    assert html =~ ~s(href="/people/#{report.id}")
    assert html =~ "Ines Vasquez"
    refute html =~ ~s(href="/people/#{manager.id}")
  end
end
