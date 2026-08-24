defmodule Leaf.Leave.Offer do
  @moduledoc """
  Which leave types a person may file against, and which dates each of them answers for.

  What somebody may ask for comes from the policy they were on then, not from what they hold a
  balance in: a type that grants nothing and is only recorded is still one they may file. A type the
  organisation has withdrawn is nobody's to file, whatever the date, since withdrawing it is saying
  it is not on offer rather than saying when it stopped being.

  The dates asked about are what decides, not today, so a type stops being offered for the dates its
  entitlement no longer covers rather than for all of them at once — which is what lets February's
  leave be filed against something that closed in March (§4.8).
  """

  import Ecto.Changeset

  alias Ecto.Changeset
  alias Leaf.Dates
  alias Leaf.Leave.Day
  alias Leaf.Leave.Request
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies
  alias Leaf.Policies.LeaveType

  @doc """
  The leave types a person may file against over the whole of `range`, in the organisation's order.

  A type offered over part of `range` is not offered over the range. One request asks for one leave
  type across every date it covers, so an entitlement that closed on the 1st cannot answer for the
  month; a type closed and offered again answers for a range the pair of them cover between them.
  """
  @spec types(Person.t(), Date.Range.t()) :: [LeaveType.t()]
  def types(person, range) do
    person
    |> offerings(range)
    |> Enum.group_by(fn {_span, entitlement} -> entitlement.leave_type_id end)
    |> Enum.filter(fn {_id, offerings} -> throughout?(offerings, range) end)
    |> Enum.map(fn {_id, [{_span, entitlement} | _rest]} -> entitlement.leave_type end)
    |> Enum.sort_by(&{&1.position, &1.name})
  end

  @doc """
  Errors on a request holding a day of a type nobody offered the person on its date.

  A form asks first and offers only what it may, so this is the same question asked of what was
  filed: it is what refuses a type from another organisation, one since withdrawn, or one whose
  entitlement closed years before the date. The refusal is about the request rather than about a
  field, the way a clashing day is, because which day it was is `types/2`'s to say.
  """
  @spec validate(Changeset.t(), Person.t()) :: Changeset.t()
  def validate(%{valid?: false} = changeset, _person), do: changeset

  def validate(changeset, person) do
    refuse(changeset, unoffered(Request.filing(changeset), person))
  end

  defp refuse(changeset, []), do: changeset

  defp refuse(changeset, [_day | _rest]) do
    add_error(changeset, :days, "hold a leave type that was not on offer on its date")
  end

  defp unoffered([], _person), do: []

  defp unoffered(days, person) do
    offerings = offerings(person, Dates.spanning(Enum.map(days, & &1.date)))

    Enum.reject(days, fn day -> Enum.any?(offerings, &offers?(&1, day)) end)
  end

  # Every entitlement the person's policies hold over `range`, each with the stretch of it they were
  # on that policy for. A stretch they were on no policy for is in none of them, so it is a date
  # nothing is offered on and no type covers the range.
  defp offerings(person, range) do
    person
    |> People.leave_policy_segments(range)
    |> Enum.flat_map(fn {span, policy_id} -> of_policy(policy_id, span) end)
  end

  defp of_policy(policy_id, span) do
    policy_id
    |> Policies.entitlements(span)
    |> Enum.reject(&(&1.leave_type.archived_at != nil))
    |> Enum.map(&{span, &1})
  end

  defp throughout?(offerings, range) do
    Enum.all?(range, fn date -> Enum.any?(offerings, &on?(&1, date)) end)
  end

  defp offers?(offering, %Day{} = day) do
    {_span, entitlement} = offering

    entitlement.leave_type_id == day.leave_type_id and on?(offering, day.date)
  end

  defp on?({span, entitlement}, date) do
    date in span and not Date.before?(date, entitlement.effective_from) and
      not closed_by?(entitlement, date)
  end

  defp closed_by?(%{effective_to: nil}, _date), do: false
  defp closed_by?(entitlement, date), do: Date.after?(date, entitlement.effective_to)
end
