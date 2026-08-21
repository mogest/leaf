defmodule Leaf.Leave.RequestTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.Leave.Request

  setup do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    %{person: person, leave_type: leave_type}
  end

  defp day(leave_type, date),
    do: %{leave_type_id: leave_type.id, date: date, hours: "8", days: "1"}

  defp request(person, leave_type, dates) do
    %Request{}
    |> Request.changeset(%{
      person_id: person.id,
      submitted_by_id: person.id,
      status: :pending,
      days: Enum.map(dates, &day(leave_type, &1))
    })
    |> Repo.insert!()
  end

  test "a request must cover at least one day", %{person: person} do
    changeset =
      Request.changeset(%Request{}, %{
        person_id: person.id,
        submitted_by_id: person.id,
        status: :pending
      })

    assert errors_on(changeset).days == ["can't be blank"]
  end

  test "amending a request may shorten it", %{person: person, leave_type: leave_type} do
    request = request(person, leave_type, [~D[2026-08-20], ~D[2026-08-21]])
    assert length(request.days) == 2

    {:ok, amended} =
      request
      |> Request.changeset(%{days: [day(leave_type, ~D[2026-08-20])]})
      |> Repo.update()

    assert [%{date: ~D[2026-08-20]}] = amended.days
  end

  test "a single day may draw on two leave types", %{person: person, leave_type: leave_type} do
    other =
      Fixtures.leave_type(%{
        organisation_id: leave_type.organisation_id,
        name: "Quarterly leave",
        position: 2
      })

    request =
      %Request{}
      |> Request.changeset(%{
        person_id: person.id,
        submitted_by_id: person.id,
        status: :pending,
        days: [
          %{leave_type_id: other.id, date: ~D[2026-08-20], hours: "7.20", days: "0.80"},
          %{leave_type_id: leave_type.id, date: ~D[2026-08-20], hours: "1.80", days: "0.20"}
        ]
      })
      |> Repo.insert!()

    assert length(request.days) == 2
  end

  test "deciding a request does not need its days loaded", %{
    person: person,
    leave_type: leave_type
  } do
    request = request(person, leave_type, [~D[2026-08-20]])
    manager = Fixtures.person(%{organisation_id: person.organisation_id})

    {:ok, decided} =
      Request
      |> Repo.get!(request.id)
      |> Request.review_changeset(%{
        status: :approved,
        reviewed_by_id: manager.id,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    assert decided.status == :approved
  end
end
