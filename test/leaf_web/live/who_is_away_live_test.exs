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
    calendar = Fixtures.calendar(%{organisation_id: organisation.id})

    Fixtures.calendar_assignment(%{person_id: person.id, calendar_id: calendar.id})

    Fixtures.public_holiday(%{
      calendar_id: calendar.id,
      date: ~D[2030-03-06],
      name: "Fair Day"
    })

    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    Fixtures.offering(%{
      person_id: person.id,
      organisation_id: organisation.id,
      leave_type_id: leave_type.id
    })

    days = [%{leave_type_id: leave_type.id, date: @date, amount: "8", unit: :hours}]
    {:ok, request} = Leave.request(person, person, %{days: days})

    %{conn: sign_in(conn, person), organisation: organisation, person: person, request: request}
  end

  test "a month shows everybody's leave, holidays and days off in one grid", context do
    {:ok, _live, html} = live(context.conn, ~p"/away?month=2030-03")

    assert html =~ "March 2030"
    assert html =~ "Rae Halloran"
    assert html =~ ~s(<td data-leave="pending")
    assert html =~ "Fair Day"
    assert html =~ ~s(data-working="no")
  end

  test "a month that is not a month reads as this one", context do
    {:ok, _live, html} = live(context.conn, ~p"/away?month[x]=1")

    assert html =~ "Who&#39;s away"
  end

  test "leave nobody has decided on reaches only whoever the record is open to", context do
    colleague =
      Fixtures.person(%{organisation_id: context.organisation.id, name: "Tova Brandt"})

    Fixtures.work_pattern(%{person_id: colleague.id})
    conn = sign_in(context.conn, colleague)

    {:ok, _live, html} = live(conn, ~p"/away?month=2030-03")

    assert html =~ "Rae Halloran"
    refute html =~ ~s(<td data-leave="pending")

    admin =
      Fixtures.person(%{
        organisation_id: context.organisation.id,
        name: "Ines Vasquez",
        role: :admin
      })

    {:ok, request} = Leave.fetch_request(context.request.id)
    {:ok, _approved} = Leave.approve(request, admin)

    {:ok, _live, html} = live(conn, ~p"/away?month=2030-03")

    assert html =~ ~s(<td data-leave="approved")
  end

  test "the month steps a month either way", context do
    {:ok, _live, html} = live(context.conn, ~p"/away?month=2030-03")

    assert html =~ "/away?month=2030-02"
    assert html =~ "/away?month=2030-04"
  end
end
