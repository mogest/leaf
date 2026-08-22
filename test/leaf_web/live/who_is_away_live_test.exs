defmodule LeafWeb.WhoIsAwayLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @date ~D[2030-03-04]

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id, name: "Rae Halloran"})
    Fixtures.work_pattern(%{person_id: person.id})
    calendar = Fixtures.holiday_calendar(%{organisation_id: organisation.id})

    Fixtures.calendar_assignment(%{person_id: person.id, holiday_calendar_id: calendar.id})

    Fixtures.public_holiday(%{
      holiday_calendar_id: calendar.id,
      date: ~D[2030-03-06],
      name: "Fair Day"
    })

    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})
    days = [%{leave_type_id: leave_type.id, date: @date, amount: "8", unit: :hours}]
    {:ok, _request} = Leave.request(person, person, %{days: days})

    %{conn: sign_in(conn, person), person: person}
  end

  test "a month shows everybody's leave, holidays and days off in one grid", context do
    {:ok, _live, html} = live(context.conn, ~p"/away?month=2030-03")

    assert html =~ "March 2030"
    assert html =~ "Rae Halloran"
    assert html =~ ~s(data-leave="pending")
    assert html =~ "Fair Day"
    assert html =~ ~s(data-working="no")
  end

  test "the month steps a month either way", context do
    {:ok, _live, html} = live(context.conn, ~p"/away?month=2030-03")

    assert html =~ "/away?month=2030-02"
    assert html =~ "/away?month=2030-04"
  end
end
