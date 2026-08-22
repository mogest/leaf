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

  defp day(leave_type, date, attrs \\ %{}) do
    Map.merge(
      %{leave_type_id: leave_type.id, date: date, amount: "8", unit: :hours, hours_in_day: "8"},
      attrs
    )
  end

  defp changeset(person, days) do
    Request.changeset(
      %Request{person_id: person.id, submitted_by_id: person.id, status: :pending},
      %{days: days}
    )
  end

  test "a request must cover at least one day", %{person: person} do
    assert errors_on(changeset(person, [])).days == ["can't be blank"]
  end

  test "a day the person does not work is refused", %{person: person, leave_type: leave_type} do
    days = [day(leave_type, ~D[2026-08-22], %{hours_in_day: "0"})]

    assert [%{date: ["is not a working day"]}] = errors_on(changeset(person, days)).days
  end

  test "amending a request may shorten it", %{person: person, leave_type: leave_type} do
    request =
      Repo.insert!(
        changeset(person, [day(leave_type, ~D[2026-08-20]), day(leave_type, ~D[2026-08-21])])
      )

    assert length(request.days) == 2

    {:ok, amended} =
      request |> Request.changeset(%{days: [day(leave_type, ~D[2026-08-20])]}) |> Repo.update()

    assert [%{date: ~D[2026-08-20]}] = amended.days
  end

  test "a single day may draw on two leave types", %{person: person, leave_type: leave_type} do
    other =
      Fixtures.leave_type(%{
        organisation_id: leave_type.organisation_id,
        name: "Quarterly leave",
        position: 2
      })

    days = [
      day(other, ~D[2026-08-20], %{amount: "7.20"}),
      day(leave_type, ~D[2026-08-20], %{amount: "1.80"})
    ]

    assert length(Repo.insert!(changeset(person, days)).days) == 2
  end

  test "a decision must say who made it", %{person: person, leave_type: leave_type} do
    request = Repo.insert!(changeset(person, [day(leave_type, ~D[2026-08-20])]))

    errors = errors_on(Request.review_changeset(request, %{status: :approved}))

    assert errors.reviewed_by_id == ["can't be blank"]
    assert errors.reviewed_at == ["can't be blank"]
  end

  test "a decided request cannot be put back to pending", %{
    person: person,
    leave_type: leave_type
  } do
    decided = %{
      status: :approved,
      reviewed_by_id: person.id,
      reviewed_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    approved =
      person
      |> changeset([day(leave_type, ~D[2026-08-20])])
      |> Repo.insert!()
      |> Request.review_changeset(decided)
      |> Repo.update!()

    changeset = Request.review_changeset(approved, %{decided | status: :pending})

    assert errors_on(changeset).status == ["is invalid"]
  end
end
